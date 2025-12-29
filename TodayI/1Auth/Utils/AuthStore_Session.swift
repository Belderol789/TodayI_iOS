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
  func ensureSignedIn() async {
    // If already a registered user, do nothing
    if let u = Auth.auth().currentUser, !u.isAnonymous {
      print("Anonymous sign-in failed")
      return
    }
    
    if let u = Auth.auth().currentUser {
      await loadOrCreateProfile(for: u)
    } else {
      do {
        let result = try await Auth.auth().signInAnonymously()
        await loadOrCreateProfile(for: result.user)
      } catch {
        print("Anonymous sign-in failed:", error)
      }
    }
  }
  
  func loadOrCreateProfile(for user: FirebaseAuth.User) async {
    let uid = user.uid
    let userDoc = db.collection("users").document(uid)
    
    do {
      let snap = try await userDoc.getDocument()
      let isAnon = user.isAnonymous                 // ← SOURCE OF TRUTH
      
      if snap.exists, let data = snap.data() {
        let uname = data["username"] as? String ?? Self.defaultUsername(for: uid)
        let email = data["email"] as? String
        let photoURL = data["photoURL"] as? String
        
        // If Firestore has stale isAnonymous, fix it
        if (data["isAnonymous"] as? Bool) != isAnon {
          try await userDoc.updateData([
            "isAnonymous": isAnon,
            "updatedAt": FieldValue.serverTimestamp()
          ])
        }
        
        upsertLocalUser(uid: uid, username: uname, email: email, isAnonymous: isAnon)
        publish(uid: uid, username: uname, email: email, isAnonymous: isAnon, photoURL: photoURL)
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
      
      upsertLocalUser(uid: uid, username: uname, email: user.email, isAnonymous: isAnon)
      publish(uid: uid, username: uname, email: email, isAnonymous: isAnon)
      
    } catch {
      print("Failed to load/create user profile:", error)
      // Fallback still uses Firebase truth:
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
