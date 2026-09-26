import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftData
import Foundation

extension AuthStore {

  // MARK: - Delete account

  /// Deletes the account and everything attached to it.
  ///
  /// The erasure itself happens in the `deleteAccountData` Cloud Function, not here.
  /// Security rules put three things permanently out of the client's reach — the user's
  /// Storage files, their comments on *other people's* posts, and their uid inside other
  /// users' `blockedUsers` arrays — so a client-side wipe could never be complete no
  /// matter how carefully it was written.
  ///
  /// It also fixes an ordering hazard rather than just missing data. The old version
  /// deleted Firestore first and the Auth user last, so `requiresRecentLogin` — the
  /// *expected* error for anyone who hadn't signed in recently — destroyed the user's
  /// entire history while leaving the account alive, with nothing left to retry. The
  /// Admin SDK has no recent-login requirement, so that failure mode is gone and there
  /// is no longer any reason to prompt for re-authentication.
  ///
  /// Local data is wiped only after the server confirms, so a failed call leaves the
  /// user exactly where they started.
  func deleteAccount() async throws {
    guard Auth.auth().currentUser != nil, let uid = userID else {
      throw DeleteError.notSignedIn
    }

    LoggerManager.instance.logFirebaseCall()
    do {
      let functions = Functions.functions(region: "asia-southeast1")
      _ = try await functions.httpsCallable("deleteAccountData").call()
      print("✅ deleteAccountData succeeded for \(uid)")
    } catch {
      print("❌ deleteAccountData failed:", error)
      throw DeleteError.remoteFailed(error.localizedDescription)
    }

    // Stop the per-user milestone topic before the session goes away.
    NotificationManager.shared.unsubscribePreviousUserTopicIfNeeded()

    wipeLocalData(uid: uid)

    // The Auth user no longer exists server-side, so the cached session is stale.
    // Clear it explicitly rather than letting the next token refresh fail.
    try? Auth.auth().signOut()
    await ensureSignedIn()
  }

  // MARK: - Local wipe

  private func wipeLocalData(uid: String) {
    do {
      try context.fetch(FetchDescriptor<MemoryModel>()).forEach { context.delete($0) }
      try context.fetch(FetchDescriptor<UserModel>()).forEach { context.delete($0) }
      try context.fetch(FetchDescriptor<DateModel>()).forEach { context.delete($0) }
      // Without this the next account inherits the previous one's blocks, which is both
      // wrong and impossible for the new user to explain or undo.
      try context.fetch(FetchDescriptor<BlockedUserList>()).forEach { context.delete($0) }
      try context.save()
    } catch {
      print("wipeLocalData error:", error)
    }

    // Must match the directories SwiftDataManager actually writes to — images go to
    // "memories", not "images". The old list said ["audio", "images"], so every photo
    // and every video survived account deletion on disk.
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    for folder in ["memories", "audio", "videos"] {
      if let url = docs?.appendingPathComponent(folder) {
        try? FileManager.default.removeItem(at: url)
      }
    }
    if let profileImg = docs?.appendingPathComponent("profile_\(uid).jpg") {
      try? FileManager.default.removeItem(at: profileImg)
    }
  }

  enum DeleteError: LocalizedError {
    case notSignedIn
    case remoteFailed(String)

    var errorDescription: String? {
      switch self {
      case .notSignedIn:
        return "No signed-in account found."
      case .remoteFailed(let reason):
        // Say plainly that nothing was deleted — a half-trusted delete is worse than a
        // clear failure when the whole point is that the data is gone.
        return "Your account could not be deleted, so nothing was removed. Please check your connection and try again. (\(reason))"
      }
    }
  }
}
