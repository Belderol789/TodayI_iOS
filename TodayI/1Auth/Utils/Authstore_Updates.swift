//
//  Authstore_Updates.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/25/25.
//

import Foundation
import SwiftData
import FirebaseFirestore

extension AuthStore {
  
  // MARK: - Username editing
  func updateUsername(_ newName: String) async {
    guard let uid = userID else { return }
    do {
      try await db.collection("users").document(uid).updateData([
        "username": newName,
        "updatedAt": FieldValue.serverTimestamp()
      ])
      // Local cache + state
      if let local = try? fetchLocalUser(uid: uid) {
        local.username = newName
        local.updatedAt = .now
        try? context.save()
      }
      self.username = newName
      renameOwnMemories(uid: uid, to: newName)
    } catch {
      print("Update username failed:", error)
    }
  }
  
  func updateProfilePhoto(url: String, localImage: UIImage?) async {
    guard let uid = userID else { return }
    
    var localPath: String? = nil
    
    // 1. Save image locally (if provided)
    if let image = localImage,
       let data = image.jpegData(compressionQuality: 0.9) {
      do {
        let filename = "profile_\(uid).jpg"
        let fileURL = FileManager.default
          .urls(for: .documentDirectory, in: .userDomainMask)
          .first!
          .appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        localPath = fileURL.path
        profileImage = image
      } catch {
        print("⚠️ Failed to save local profile image:", error)
      }
    }
    
    // 2. Update Firestore with remote-only reference
    do {
      try await db.collection("users").document(uid).updateData([
        "photoURL": url,
        "updatedAt": FieldValue.serverTimestamp()
      ])
    } catch {
      print("⚠️ Firestore profile photo update failed:", error)
    }
    
    // 3. Sync with local SwiftData
    if let local = try? fetchLocalUser(uid: uid) {
      local.photoURL = url
      local.localPhotoPath = localPath
      local.updatedAt = .now
      try? context.save()
    }
    
    // 4. Publish change to UI
    await MainActor.run {
      self.photoURL = url
    }
  }
  

  /// Each memory keeps a copy of its author's name, so a rename has to reach them. This
  /// does the device's copies at once; `onUserProfileUpdated` does the Firestore copies —
  /// memories and comments — on the server, because rules allow no edit to a posted comment.
  private func renameOwnMemories(uid: String, to newName: String) {
    do {
      let mine = try context.fetch(FetchDescriptor<MemoryModel>(
        predicate: #Predicate { $0.userID == uid }
      ))
      for memory in mine where memory.username != newName {
        memory.username = newName
      }
      try context.save()
    } catch {
      print("⚠️ Couldn't rename local memories:", error)
    }
    NotificationCenter.default.post(
      name: .authorNameDidChange, object: nil,
      userInfo: ["uid": uid, "username": newName]
    )
    NotificationCenter.default.post(name: .memoryDidChangeLocally, object: nil)
  }
}
