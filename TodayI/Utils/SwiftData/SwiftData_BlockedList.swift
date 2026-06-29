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
  // MARK: - Add Blocked User
  func addBlockedUser(_ targetUID: String) {
    // 1. Local SwiftData
    do {
      if let list = try context.fetch(FetchDescriptor<BlockedUserList>()).first {
        if !list.users.contains(targetUID) {
          list.users.append(targetUID)
          try context.save()
        }
      } else {
        context.insert(BlockedUserList(users: [targetUID]))
        try context.save()
      }
    } catch {
      print("❌ addBlockedUser SwiftData error:", error)
    }

    // 2. Firestore — bidirectional: both users block each other
    guard let myUID = Auth.auth().currentUser?.uid else { return }
    let db = Firestore.firestore()
    // Add target to my blockedUsers
    db.collection("users").document(myUID).setData(
      ["blockedUsers": FieldValue.arrayUnion([targetUID])], merge: true
    )
    // Add me to target's blockedUsers
    db.collection("users").document(targetUID).setData(
      ["blockedUsers": FieldValue.arrayUnion([myUID])], merge: true
    )
  }
  
  // MARK: - Fetch Blocked Users
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
  
  // MARK: - Remove Blocked User (optional helper)
  func removeBlockedUser(_ userID: String) {
    do {
      if let list = try context.fetch(FetchDescriptor<BlockedUserList>()).first {
        if let index = list.users.firstIndex(of: userID) {
          list.users.remove(at: index)
          try context.save()
          print("✅ Removed blocked user: \(userID)")
        } else {
          print("⚠️ User not found in blocked list: \(userID)")
        }
      }
    } catch {
      print("❌ Failed to remove blocked user: \(error.localizedDescription)")
    }
  }
}
