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

    // Tear the app down *before* deleting anything. Home and Calendar keep the year's
    // moods in plain `@State` arrays of `DateModel`, and Settings is a sheet over Home,
    // so Home was still alive during the wipe: the next render read `moodRaws` on a
    // deleted object and SwiftData crashed ("backing data was detached from a context")
    // — mid-sequence, so the old account's memories survived into the new one.
    // `RootView` swaps to a placeholder on `isResettingSession`; the pause lets SwiftUI
    // actually dismantle those screens before their models disappear.
    beginSessionReset()
    try? await Task.sleep(nanoseconds: 400_000_000)

    // Stop the per-user milestone topic before the session goes away.
    NotificationManager.shared.unsubscribePreviousUserTopicIfNeeded()

    wipeLocalData(uid: uid)

    // The Auth user no longer exists server-side, so the cached session is stale.
    // Clear it explicitly rather than letting the next token refresh fail.
    try? Auth.auth().signOut()
    await ensureSignedIn()

    // A new `RootView` identity: every screen starts empty for the new account.
    finishSessionReset()
  }

  // MARK: - Local wipe

  private func wipeLocalData(uid: String) {
    do {
      try context.delete(model: MemoryModel.self)
      try context.delete(model: UserModel.self)
      // `DateModel` has no owner field — it's the calendar and the streak. Leaving it would
      // hand the next account the previous one's whole year of moods.
      try context.delete(model: DateModel.self)
      // Without this the next account inherits the previous one's blocks, which is both
      // wrong and impossible for the new user to explain or undo.
      try context.delete(model: BlockedUserList.self)
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
    // Cached copies of rules-protected media fetched on this device.
    ProtectedMediaStore.clearCache()
    // The Home Screen widget reads its own snapshot, not the store — reset it, or it keeps
    // showing the deleted account's streak.
    StreakSnapshot.write(days: 0, loggedToday: false)
  }

  enum DeleteError: LocalizedError {
    case notSignedIn
    case remoteFailed(String)

    var errorDescription: String? {
      switch self {
      case .notSignedIn:
        return "No signed-in account found."
      case .remoteFailed(let reason):
        // Not "nothing was removed": the server deletes in stages, and a failure partway
        // (a dropped connection) can leave some of it already gone. That promise was false
        // the first time this failed for real. What *is* true: the account still exists,
        // and `deleteAccountData` is idempotent, so trying again finishes the job.
        return "Your account wasn't fully deleted. Please check your connection and try again — trying again picks up where it stopped. (\(reason))"
      }
    }
  }
}
