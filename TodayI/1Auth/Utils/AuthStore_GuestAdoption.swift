import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseCrashlytics

extension AuthStore {

  // MARK: - Guest memory adoption

  /// Hands memories written by an anonymous guest on this device to the account now in use.
  ///
  /// A memory's `userID` is fixed when it's written, and Home and the calendar's day view
  /// only show the signed-in account's memories. Every uid change therefore hid a guest's
  /// entries while leaving them on disk: signing in with an Apple ID that already had an
  /// account (Firebase signs into that account instead of upgrading the guest), signing out
  /// to a fresh guest, or recovering from a dead session. To the person it looked exactly
  /// like losing their journal.
  ///
  /// Only memories owned by **anonymous** users move. A registered account's memories stay
  /// with it, so signing out of one account and into another never hands over someone
  /// else's entries; they reappear when that account signs back in. Guest memories were
  /// never uploaded (guests can't post Global or buy Premium), so nothing remote needs
  /// moving: they keep `needsCloudBackup`, and a Premium account backs them up under its
  /// own uid.
  func adoptGuestMemories(into uid: String, username: String) {
    do {
      let guestIDs = try context.fetch(FetchDescriptor<UserModel>(
        predicate: #Predicate { $0.isAnonymous && $0.id != uid }
      )).map(\.id)
      guard !guestIDs.isEmpty else { return }

      let orphans = try context.fetch(FetchDescriptor<MemoryModel>(
        predicate: #Predicate { guestIDs.contains($0.userID) }
      ))
      guard !orphans.isEmpty else { return }

      for memory in orphans {
        memory.userID = uid
        memory.username = username
      }
      try context.save()
      print("🧳 Adopted \(orphans.count) guest memor\(orphans.count == 1 ? "y" : "ies") into \(uid)")
      // Home and the calendar refresh on this signal.
      NotificationCenter.default.post(name: .memoryDidChangeLocally, object: nil)
    } catch {
      print("❌ adoptGuestMemories failed:", error)
    }
  }

  // MARK: - Guest → existing account

  /// Signs a guest into an Apple or Google ID that already has a TodayI account, and makes
  /// the two one account: the guest's memories and blocks move to the account, then the
  /// guest itself is retired on the server.
  ///
  /// (A *new* Apple or Google ID never comes here — `link(with:)` upgrades the guest in
  /// place, same uid, so it already is one account.)
  func switchFromGuest(_ guest: FirebaseAuth.User, using credential: AuthCredential) async throws {
    // Captured while the guest is still signed in. The token is what proves to the server
    // that this guest is ours to retire; the blocks would otherwise be replaced by the
    // account's own list when its profile loads.
    let guestToken = try? await guest.getIDToken()
    let guestBlocks = (try? context.fetch(FetchDescriptor<BlockedUserList>()).first?.users) ?? []

    let result = try await Auth.auth().signIn(with: credential)
    let uid = result.user.uid
    // Adopts the guest's on-device memories (`adoptGuestMemories`).
    await loadOrCreateProfile(for: result.user)
    await waitForProfileLoad(uid)
    await carryOverBlocks(guestBlocks, to: uid)

    guard let guestToken else {
      print("⚠️ No token for guest \(guest.uid) — it stays until Firebase prunes it")
      return
    }
    do {
      _ = try await Functions.functions(region: "asia-southeast1")
        .httpsCallable("retireGuestAccount")
        .call(["guestToken": guestToken])
      print("👋 Retired guest \(guest.uid)")
    } catch {
      // Not fatal: the person is signed in with everything moved over. What's left is an
      // empty guest that Firebase's anonymous cleanup — and `onAuthUserDeleted` — remove.
      print("⚠️ Couldn't retire guest \(guest.uid):", error)
      Crashlytics.crashlytics().record(error: error, userInfo: ["context": "retireGuestAccount"])
    }
  }

  /// The auth listener may be loading this profile concurrently; its block-list sync would
  /// overwrite a merge made before it finishes.
  private func waitForProfileLoad(_ uid: String) async {
    var waited = 0
    while profileLoadsInFlight.contains(uid), waited < 100 {   // at most ~5 seconds
      try? await Task.sleep(nanoseconds: 50_000_000)
      waited += 1
    }
  }

  /// Adds the guest's blocks to the account, both in Firestore and on the device.
  private func carryOverBlocks(_ guestBlocks: [String], to uid: String) async {
    do {
      let list = try context.fetch(FetchDescriptor<BlockedUserList>()).first
      let current = Set(list?.users ?? [])
      let missing = guestBlocks.filter { !current.contains($0) && $0 != uid }
      guard !missing.isEmpty else { return }
      try await db.collection("users").document(uid)
        .updateData(["blockedUsers": FieldValue.arrayUnion(missing)])
      if let list {
        list.users = Array(current) + missing
      } else {
        context.insert(BlockedUserList(users: missing))
      }
      try context.save()
      print("🧳 Carried over \(missing.count) block(s) from the guest")
    } catch {
      print("⚠️ Couldn't carry over guest blocks:", error)
    }
  }
}
