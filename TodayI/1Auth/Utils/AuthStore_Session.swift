//
//  AuthStore_Session.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/25/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

import SwiftData

extension AuthStore {
  // MARK: - Entry point
  /// Resolves the session at launch (and after a sign-out or account deletion).
  ///
  /// Single-flight: a second caller waits for the first instead of starting its own.
  func ensureSignedIn() async {
    if let running = signInTask {
      await running.value
      return
    }
    let task = Task { await self.resolveSession() }
    signInTask = task
    await task.value
    signInTask = nil
    initialSessionVerified = true
    if let uid = Auth.auth().currentUser?.uid {
      NotificationManager.shared.subscribeUserTopic(uid: uid)
    }
  }

  /// Uses the cached Keychain session only if the server still knows it.
  ///
  /// The Keychain outlives the app and the account. A *registered* cached user used to be
  /// trusted outright ("already signed in, do nothing"), so after its account was deleted
  /// — by `deleteAccountData`, a console wipe, anything — the app showed that person as
  /// signed in to an account that no longer existed. Its ID token can stay valid for up
  /// to an hour, so Firestore even accepted writes for a while, which made it look fine.
  private func resolveSession() async {
    if let user = Auth.auth().currentUser {
      if await isSessionAlive(user) {
        await loadOrCreateProfile(for: user)
        return
      }
      print("⚠️ Cached session \(user.uid) no longer exists server-side — starting fresh")
      try? Auth.auth().signOut()
    }
    do {
      let result = try await Auth.auth().signInAnonymously()
      await loadOrCreateProfile(for: result.user)
    } catch {
      print("Anonymous sign-in failed:", error)
      // Still unblock the UI so user doesn't see a permanent loading screen
      isSessionReady = true
    }
  }

  /// `reload()` asks the Auth server about this user. Only answers that mean "this account
  /// is gone" count as dead; being offline must not throw someone out of their journal, so
  /// any other failure trusts the cached session.
  private func isSessionAlive(_ user: FirebaseAuth.User) async -> Bool {
    do {
      try await user.reload()
      return true
    } catch {
      guard let code = AuthErrorCode(rawValue: (error as NSError).code) else { return true }
      switch code {
      case .userNotFound, .userDisabled, .invalidUserToken, .userTokenExpired:
        return false
      default:
        return true
      }
    }
  }
  
  func loadOrCreateProfile(for user: FirebaseAuth.User, isRecoveryAttempt: Bool = false) async {
    let uid = user.uid
    // The listener and an explicit caller often load the same user at once. Two
    // concurrent loads of a dead session each ran the recovery below and each created an
    // anonymous account.
    guard !profileLoadsInFlight.contains(uid) else { return }
    profileLoadsInFlight.insert(uid)
    defer { profileLoadsInFlight.remove(uid) }
    let userDoc = db.collection("users").document(uid)
    
    do {
      let snap = try await userDoc.getDocument()
      let isAnon = user.isAnonymous                 // ← SOURCE OF TRUTH
      
      if snap.exists, let data = snap.data() {
        let uname = data["username"] as? String ?? Self.defaultUsername(for: uid)
        let email = data["email"] as? String
        let photoURL = data["photoURL"] as? String
        let isRestricted = data["isRestricted"] as? Bool ?? false
        let remoteBlocked = data["blockedUsers"] as? [String] ?? []

        // If Firestore has stale isAnonymous, fix it
        if (data["isAnonymous"] as? Bool) != isAnon {
          try await userDoc.updateData([
            "isAnonymous": isAnon,
            "updatedAt": FieldValue.serverTimestamp()
          ])
        }

        syncBlockedUsers(remoteBlocked)
        // If the server purged this user's backup while Premium was lapsed, every local
        // memory has to go back in the upload queue — otherwise resubscribing restores
        // nothing written before the purge.
        CloudBackupService.reflagIfPurged(
          backupPrunedAt: (data["backupPrunedAt"] as? Timestamp)?.dateValue(),
          context: context
        )

        // `admin` is one of the two fields the Firestore rules already reserve as
        // console-only (`touchesAdminFields()` — the owner can write their own doc, but
        // not this). Reusing that primitive here rather than a client-facing "subscribe
        // to admin alerts" toggle: reports carry another user's uid and the memory they
        // reported, and there's no reason to let any regular user discover a button that
        // exposes moderation traffic. Set `admin: true` on your own user doc from the
        // console once, and the next sign-in on that account subscribes automatically —
        // the same queued, APNs-safe path every other topic already goes through.
        NotificationManager.shared.syncAdminReportsTopic(isAdmin: data["admin"] as? Bool == true)
        upsertLocalUser(uid: uid, username: uname, email: email, isAnonymous: isAnon)
        adoptGuestMemories(into: uid, username: uname)
        publish(uid: uid, username: uname, email: email, isAnonymous: isAnon, photoURL: photoURL, isRestricted: isRestricted)
        return
      }
      
      // Create minimal doc
      let uname = Self.defaultUsername(for: uid)
      let payload: [String: Any] = [
        "username": uname,
        "email": user.email as Any,
        "isAnonymous": isAnon,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp()
      ]
      try await userDoc.setData(payload)
      // A brand-new account is never an admin — drop any subscription this device kept
      // from whoever used it before.
      NotificationManager.shared.syncAdminReportsTopic(isAdmin: false)
      
      upsertLocalUser(uid: uid, username: uname, email: user.email, isAnonymous: isAnon)
      adoptGuestMemories(into: uid, username: uname)
      publish(uid: uid, username: uname, email: email, isAnonymous: isAnon)
      
    } catch {
      print("Failed to load/create user profile:", error)

      // A persisted Firebase Auth session can be dead: its underlying user record was
      // deleted (our own `deleteAccountData`, a console cleanup, Firebase's own
      // anonymous-account pruning) while Keychain still cached its credentials.
      // `Auth.auth().currentUser` then keeps returning that uid — `ensureSignedIn()`
      // trusts it without ever verifying the backend still recognizes it — and every
      // write attempted as that uid is denied. Under this ruleset, creating your own
      // `users/{uid}` doc has exactly one gate — `isOwner(uid)` — so a permission-denied
      // right here has essentially one honest explanation: the session, not the rule.
      //
      // The bug this replaces: the code below used to `publish(uid: uid, ...)` on ANY
      // failure, including this one — so the app looked signed in and stayed that way
      // forever, while every future read and write kept silently failing against a
      // session the server had already discarded. That is why "a new account, no
      // login" could still never get its profile document created.
      let isPermissionDenied = (error as NSError).domain == FirestoreErrorDomain
        && (error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue

      if isPermissionDenied, !isRecoveryAttempt {
        print("⚠️ Treating this as a dead session — signing out and starting fresh")
        try? Auth.auth().signOut()
        do {
          let result = try await Auth.auth().signInAnonymously()
          // Bounded to one retry: a real rule problem must not loop forever.
          await loadOrCreateProfile(for: result.user, isRecoveryAttempt: true)
        } catch {
          print("Recovery sign-in also failed:", error)
          isSessionReady = true
        }
        return
      }

      // Any other failure (offline, a genuine rule change) still needs the UI unblocked
      // rather than stuck loading — but never past a *verified* recovery attempt, so a
      // second dead session doesn't quietly get published as if it worked.
      guard !isPermissionDenied else {
        isSessionReady = true
        return
      }
      let uname = Self.defaultUsername(for: uid)
      upsertLocalUser(uid: uid, username: uname, email: user.email, isAnonymous: user.isAnonymous)
      publish(uid: uid, username: uname, email: user.email, isAnonymous: user.isAnonymous)
    }
  }
  
  // MARK: - Helpers
  private func upsertLocalUser(uid: String, username: String, email: String?, isAnonymous: Bool) {
    do {
      let fetch = FetchDescriptor<UserModel>(predicate: #Predicate { $0.id == uid })
      if let existing = try context.fetch(fetch).first {
        existing.username = username
        existing.email = email
        existing.isAnonymous = isAnonymous
        existing.updatedAt = .now
      } else {
        let model = UserModel(id: uid, username: username, email: email, isAnonymous: isAnonymous)
        context.insert(model)
      }
      try context.save()
    } catch {
      print("SwiftData upsert user failed:", error)
    }
  }
  
  func syncBlockedUsers(_ remoteList: [String]) {
    do {
      let lists = try context.fetch(FetchDescriptor<BlockedUserList>())
      if let list = lists.first {
        // Remote wins rather than merging. Merging meant an unblock was undone on the
        // next launch — the removed uid was still in `remoteList`, got unioned back in,
        // and the block silently returned. Firestore applies pending offline writes to
        // its own cache, so a block made without a connection is already present here
        // and isn't lost by taking the remote list as the source of truth.
        list.users = remoteList
      } else {
        context.insert(BlockedUserList(users: remoteList))
      }
      try context.save()
    } catch {
      print("syncBlockedUsers error:", error)
    }
  }

  func fetchLocalUser(uid: String) throws -> UserModel? {
    let fetch = FetchDescriptor<UserModel>(predicate: #Predicate { $0.id == uid })
    return try context.fetch(fetch).first
  }
  
  func startListening() {
    authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
      guard let self else { return }
      print("Auth changed. user: \(user?.uid ?? "none"), providers:", user?.providerData.map { $0.providerID } ?? [])
      
      Task { @MainActor in
        if let user {
          // Launch belongs to `ensureSignedIn`, which checks the cached session with the
          // server first. Acting here before that loaded a profile for a session that
          // might already be gone — and raced it into creating extra accounts.
          guard self.initialSessionVerified else { return }
          await self.loadOrCreateProfile(for: user)
          NotificationManager.shared.subscribeUserTopic(uid: user.uid)
        } else {
          // IMPORTANT:
          // Do NOT create a new anonymous user here.
          // During credential linking / reauth, Firebase can briefly report `user == nil`.
          // Anonymous creation should be handled by your explicit entry points (ensureSignedIn / signOutToGuest).
          NotificationManager.shared.unsubscribePreviousUserTopicIfNeeded()
          print("Auth changed: signed out (waiting for ensureSignedIn).")
        }
      }
    }
  }
  
  func signOutToGuest() async {
    do {
      try Auth.auth().signOut()
    } catch {
      print("Sign out failed:", error)
    }
    NotificationManager.shared.unsubscribePreviousUserTopicIfNeeded()
    await ensureSignedIn() // creates a fresh anonymous user
  }
}
