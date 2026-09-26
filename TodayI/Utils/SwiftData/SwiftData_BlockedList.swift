//
//  SwiftData_BlockedList.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/19/25.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

@Model
final class BlockedUserList {
  @Attribute(.unique) var id: String = "blocked_users"
  var users: [String]

  init(users: [String] = []) {
    self.users = users
  }
}

extension SwiftDataManager {

  // MARK: - Block

  /// Blocks a user locally, then mirrors it to Firestore in both directions.
  ///
  /// Local first so the feed hides them instantly — `GlobalFeedView` observes
  /// `BlockedUserList` through `@Query`, so the row disappears without a refetch.
  ///
  /// The Firestore half is **awaited** now. It used to be two bare `setData` calls with
  /// no `await` and no error handling, so a denied or failed write produced a block that
  /// existed only on this device and silently evaporated on the next reinstall.
  @discardableResult
  func addBlockedUser(_ targetUID: String) async -> Bool {
    applyBlockLocally(targetUID, blocked: true)

    guard let myUID = Auth.auth().currentUser?.uid else { return false }
    LoggerManager.instance.logFirebaseCall()
    let db = Firestore.firestore()

    do {
      // My list: they go in.
      try await db.collection("users").document(myUID)
        .setData(["blockedUsers": FieldValue.arrayUnion([targetUID])], merge: true)
      // Their list: I go in. Rules allow adding only yourself to someone else's list,
      // which is exactly this write — the reciprocal half of a block.
      try await db.collection("users").document(targetUID)
        .setData(["blockedUsers": FieldValue.arrayUnion([myUID])], merge: true)
      print("✅ Blocked \(targetUID)")
      return true
    } catch {
      print("❌ addBlockedUser Firestore error:", error)
      return false
    }
  }

  // MARK: - Unblock

  /// Unblocks a user locally **and remotely**.
  ///
  /// This used to touch only SwiftData, while `syncBlockedUsers` merged the remote list
  /// back in on every launch — so an unblock survived until the app was next opened and
  /// then silently reversed itself. Unblocking was, in practice, impossible.
  ///
  /// The reciprocal entry is removed too: the other person never chose to block anyone,
  /// so leaving their copy in place would hide you from them permanently over a decision
  /// you have already reversed.
  @discardableResult
  func removeBlockedUser(_ targetUID: String) async -> Bool {
    applyBlockLocally(targetUID, blocked: false)

    guard let myUID = Auth.auth().currentUser?.uid else { return false }
    LoggerManager.instance.logFirebaseCall()
    let db = Firestore.firestore()

    do {
      try await db.collection("users").document(myUID)
        .setData(["blockedUsers": FieldValue.arrayRemove([targetUID])], merge: true)
      print("✅ Unblocked \(targetUID)")
    } catch {
      print("❌ removeBlockedUser (own list) Firestore error:", error)
      return false
    }

    // Best-effort: the current rule permits *adding* yourself to another user's
    // blockedUsers, and may not permit removing yourself. If this is denied the unblock
    // still works for you, but they keep a stale block — see CLAUDE.md.
    do {
      try await db.collection("users").document(targetUID)
        .setData(["blockedUsers": FieldValue.arrayRemove([myUID])], merge: true)
    } catch {
      print("⚠️ Could not clear reciprocal block on \(targetUID) — rule may deny it:", error)
    }
    return true
  }

  // MARK: - Fetch

  func fetchBlockedUsers() -> [String] {
    do {
      if let list = try context.fetch(FetchDescriptor<BlockedUserList>()).first {
        return list.users
      }
    } catch {
      print("❌ Failed to fetch blocked users: \(error.localizedDescription)")
    }
    return []
  }

  // MARK: - Local write

  private func applyBlockLocally(_ targetUID: String, blocked: Bool) {
    do {
      let list = try context.fetch(FetchDescriptor<BlockedUserList>()).first
        ?? {
          let fresh = BlockedUserList()
          context.insert(fresh)
          return fresh
        }()

      if blocked {
        guard !list.users.contains(targetUID) else { return }
        list.users.append(targetUID)
      } else {
        guard let idx = list.users.firstIndex(of: targetUID) else { return }
        list.users.remove(at: idx)
      }
      try context.save()
    } catch {
      print("❌ applyBlockLocally error:", error)
    }
  }
}
