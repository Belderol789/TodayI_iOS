import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import SwiftData
import Foundation

extension AuthStore {

  // MARK: - Delete account

  /// Deletes all Firestore data, Storage files, SwiftData records, and the Firebase Auth user.
  /// Requires the user to have signed in recently; throws `AuthErrorCode.requiresRecentLogin`
  /// if re-authentication is needed — callers should catch that and prompt the user to sign in again.
  func deleteAccount() async throws {
    guard let user = Auth.auth().currentUser, let uid = userID else {
      throw DeleteError.notSignedIn
    }

    // 1. Firestore: delete subcollections then the user doc.
    //    Cloud Firestore doesn't cascade-delete subcollections, so we delete them explicitly.
    let db = Firestore.firestore()
    let userDoc = db.collection("users").document(uid)

    for sub in ["memories", "notifications", "dates"] {
      let snap = try await userDoc.collection(sub).getDocuments()
      let batch = db.batch()
      snap.documents.forEach { batch.deleteDocument($0.reference) }
      try await batch.commit()
    }

    try await userDoc.delete()

    // 2. Firebase Storage: delete the user's folder (best-effort; Storage has no recursive delete).
    let storageRef = Storage.storage().reference().child("users/\(uid)")
    if let listing = try? await storageRef.listAll() {
      for item in listing.items {
        try? await item.delete()
      }
    }

    // 3. SwiftData: wipe local records for this user.
    wipeLocalData(uid: uid)

    // 4. Firebase Auth: delete the account itself.
    //    This will throw requiresRecentLogin if the session is stale.
    try await user.delete()

    // 5. Reset published state and sign in anonymously so the app has a valid session.
    NotificationManager.shared.unsubscribePreviousUserTopicIfNeeded()
    await ensureSignedIn()
  }

  // MARK: - Local wipe

  private func wipeLocalData(uid: String) {
    do {
      let memories = try context.fetch(FetchDescriptor<MemoryModel>())
      memories.forEach { context.delete($0) }

      let users = try context.fetch(FetchDescriptor<UserModel>())
      users.forEach { context.delete($0) }

      let dates = try context.fetch(FetchDescriptor<DateModel>())
      dates.forEach { context.delete($0) }

      try context.save()
    } catch {
      print("wipeLocalData error:", error)
    }

    // Also clear cached audio/image files from Documents
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    for folder in ["audio", "images"] {
      if let url = docs?.appendingPathComponent(folder) {
        try? FileManager.default.removeItem(at: url)
      }
    }
    let profileImg = docs?.appendingPathComponent("profile_\(uid).jpg")
    if let profileImg { try? FileManager.default.removeItem(at: profileImg) }
  }

  enum DeleteError: LocalizedError {
    case notSignedIn
    var errorDescription: String? {
      switch self {
      case .notSignedIn: return "No signed-in account found."
      }
    }
  }
}
