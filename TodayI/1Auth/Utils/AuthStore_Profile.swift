//
//  AuthStore_Profile.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/25/25.
//
import FirebaseAuth
import Foundation
import SwiftData
import FirebaseFirestore

extension AuthStore {
  // MARK: - Profile bootstrap
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
}

