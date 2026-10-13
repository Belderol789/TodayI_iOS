import Foundation
import SwiftData

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
}
