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

/// How the world felt, as last seen by the app.
struct WorldMood {
  let name: String
  let lightHex: String
  let darkHex: String
  let percent: Int
  let total: Int
  let updatedAt: Date

  /// The app fetches this only when the World feed loads, so it can lag. A day old
  /// is no longer "today's mood", and showing it would be a small lie.
  var isFresh: Bool {
    Calendar.current.isDateInToday(updatedAt)
  }
}

struct StreakSnapshot {
  let days: Int
  let loggedToday: Bool
  /// Nil when the app has never published — a fresh install, or the App Group
  /// capability missing on one of the two targets.
  let updatedAt: Date?
  let world: WorldMood?

  static let appGroup = "group.com.kuzostudiosph.TodayI"

  private enum Key {
    static let days = "streak.days"
    static let loggedToday = "streak.loggedToday"
    static let updatedAt = "streak.updatedAt"
    static let worldMood = "world.mood"
    static let worldMoodLightHex = "world.moodLightHex"
    static let worldMoodDarkHex = "world.moodDarkHex"
    static let worldPercent = "world.percent"
    static let worldTotal = "world.total"
    static let worldUpdatedAt = "world.updatedAt"
  }

  static var placeholder: StreakSnapshot {
    StreakSnapshot(
      days: 5, loggedToday: true, updatedAt: Date(),
      world: WorldMood(name: "Happy", lightHex: "FCD252", darkHex: "F2B833",
                       percent: 62, total: 48, updatedAt: Date())
    )
  }

  static func read() -> StreakSnapshot {
    guard let defaults = UserDefaults(suiteName: appGroup) else {
      return StreakSnapshot(days: 0, loggedToday: false, updatedAt: nil, world: nil)
    }
    return StreakSnapshot(
      days: defaults.integer(forKey: Key.days),
      loggedToday: defaults.bool(forKey: Key.loggedToday),
      updatedAt: defaults.object(forKey: Key.updatedAt) as? Date,
      world: readWorld(defaults)
    )
  }

  private static func readWorld(_ defaults: UserDefaults) -> WorldMood? {
    guard let name = defaults.string(forKey: Key.worldMood),
          let light = defaults.string(forKey: Key.worldMoodLightHex),
          let dark = defaults.string(forKey: Key.worldMoodDarkHex),
          let at = defaults.object(forKey: Key.worldUpdatedAt) as? Date
    else { return nil }
    return WorldMood(
      name: name, lightHex: light, darkHex: dark,
      percent: defaults.integer(forKey: Key.worldPercent),
      total: defaults.integer(forKey: Key.worldTotal),
      updatedAt: at
    )
  }
}
