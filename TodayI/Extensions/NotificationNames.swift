//
//  NotificationNames.swift
//  TodayI
//

import Foundation

extension Notification.Name {
  /// Posted when a memory is written outside the normal view flow — currently only
  /// by the notification mood actions, which can run while Home is already on screen
  /// (or in the background entirely). Views that show today's state observe this;
  /// without it, tapping a mood in a notification left Home still insisting you had
  /// no memories today.
  static let memoryDidChangeLocally = Notification.Name("todayi.memoryDidChangeLocally")

  /// Posted after a memory's public/private flag is written successfully.
  /// `userInfo`: `["id": String, "isPublic": Bool]`.
  ///
  /// The World feed caches `MemoryDTO`s for the whole session, and
  /// `GlobalMemoryRow` re-upserts its DTO into SwiftData on appear — so a memory
  /// switched to Personal was silently flipped back to Global the next time the feed
  /// drew it, everywhere. The feed listens to this and drops the row.
  static let memoryPrivacyDidChange = Notification.Name("todayi.memoryPrivacyDidChange")
}
