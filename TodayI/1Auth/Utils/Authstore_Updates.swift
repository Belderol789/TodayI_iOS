//
//  Authstore_Updates.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/25/25.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseFunctions

extension AuthStore {
  
  // MARK: - Username editing

  /// Why a username can't be used, phrased for Settings.
  struct UsernameError: LocalizedError {
    let errorDescription: String?
  }

  /// The same shape `claimUsername` enforces, checked first so most mistakes are caught
  /// without a round trip. The server stays the authority — it also checks the name is
  /// free and not reserved or offensive.
  static func usernameProblem(_ name: String) -> String? {
    let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard (3...20).contains(key.count) else {
      return "Usernames are 3–20 characters long."
    }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._")
    guard key.unicodeScalars.allSatisfy(allowed.contains) else {
      return "Use only letters, numbers, dots and underscores."
    }
    return nil
  }

  /// Claims the name through the `claimUsername` callable, which checks it's free and
  /// writes it in one transaction — usernames used to be written straight to the profile
  /// with no check, so two people could share one. Throws `UsernameError` with a message
  /// to show; nothing local changes unless the server accepted the name.
  func updateUsername(_ newName: String) async throws {
    guard let uid = userID else { return }
    if let problem = Self.usernameProblem(newName) {
      throw UsernameError(errorDescription: problem)
    }
    let stored: String
    do {
      let result = try await Functions.functions(region: "asia-southeast1")
        .httpsCallable("claimUsername")
        .call(["username": newName.trimmingCharacters(in: .whitespacesAndNewlines)])
      stored = (result.data as? [String: Any])?["username"] as? String ?? newName
    } catch let error as NSError where error.domain == FunctionsErrorDomain {
      print("Claim username failed:", error)
      let code = FunctionsErrorCode(rawValue: error.code)
      switch code {
      case .alreadyExists, .invalidArgument:
        throw UsernameError(errorDescription: error.localizedDescription)
      default:
        throw UsernameError(errorDescription:
          "Couldn't save that username. Check your connection and try again.")
      }
    }

    // Local cache + state. The server already wrote the profile.
    if let local = try? fetchLocalUser(uid: uid) {
      local.username = stored
      local.updatedAt = .now
      try? context.save()
    }
    self.username = stored
    renameOwnMemories(uid: uid, to: stored)
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
