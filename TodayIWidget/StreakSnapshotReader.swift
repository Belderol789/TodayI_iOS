//
//  StreakSnapshotReader.swift
//  TodayIWidget
//
//  Reader half of the contract in TodayI/Utils/StreakSnapshot.swift.
//
//  Duplicated rather than shared: the app and the widget are separate targets fed by
//  synchronised folder groups, and wiring one file into both means hand-editing the
//  Xcode project. Three string literals are cheaper to keep in step than a corrupted
//  project file — but they *must* stay in step.
//

import Foundation

struct StreakSnapshot {
  let days: Int
  let loggedToday: Bool
  /// Nil when the app has never published — a fresh install, or the App Group
  /// capability missing on one of the two targets.
  let updatedAt: Date?

  static let appGroup = "group.com.kuzostudiosph.TodayI"

  private enum Key {
    static let days = "streak.days"
    static let loggedToday = "streak.loggedToday"
    static let updatedAt = "streak.updatedAt"
  }

  static var placeholder: StreakSnapshot {
    StreakSnapshot(days: 5, loggedToday: true, updatedAt: Date())
  }

  static func read() -> StreakSnapshot {
    guard let defaults = UserDefaults(suiteName: appGroup) else {
      return StreakSnapshot(days: 0, loggedToday: false, updatedAt: nil)
    }
    return StreakSnapshot(
      days: defaults.integer(forKey: Key.days),
      loggedToday: defaults.bool(forKey: Key.loggedToday),
      updatedAt: defaults.object(forKey: Key.updatedAt) as? Date
    )
  }
}
