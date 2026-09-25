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
}
