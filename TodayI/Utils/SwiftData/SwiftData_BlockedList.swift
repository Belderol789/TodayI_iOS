//
//  SwiftData_BlockedList.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/19/25.
//

import Foundation
import SwiftData

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
  func addBlockedUser(_ userID: String) {
    do {
      // Try to fetch existing list
      if let list = try context.fetch(FetchDescriptor<BlockedUserList>()).first {
        if !list.users.contains(userID) {
          list.users.append(userID)
          try context.save()
          print("✅ Added blocked user: \(userID)")
        } else {
          print("⚠️ User already in blocked list: \(userID)")
        }
      } else {
        // Create new list if none exists
        let newList = BlockedUserList(users: [userID])
        context.insert(newList)
        try context.save()
        print("✅ Created new blocked list with: \(userID)")
      }
    } catch {
      print("❌ Failed to add blocked user: \(error.localizedDescription)")
    }
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
