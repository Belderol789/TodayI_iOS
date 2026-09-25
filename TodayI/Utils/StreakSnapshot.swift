//
//  StreakSnapshot.swift
//  TodayI
//
//  App-side writer. The widget has its own copy of this contract — see
//  TodayIWidget/StreakSnapshotReader.swift. Keep the suite name and keys identical.
//

import Foundation
import WidgetKit

/// What the widget is allowed to know.
///
/// Deliberately three values in `UserDefaults`, not the SwiftData store. A widget
/// extension is a separate process and can only reach an App Group container, so the
/// alternative was migrating the whole on-disk store into one — a real migration on a
/// shipped app, on a container that has already failed to open once. A snapshot costs
/// nothing and can't corrupt anything.
enum StreakSnapshot {
  static let appGroup = "group.com.kuzostudiosph.TodayI"
  /// Must match `TodayIWidget.kind`.
  static let widgetKind = "TodayIStreakWidget"

  enum Key {
    static let days = "streak.days"
    static let loggedToday = "streak.loggedToday"
    static let updatedAt = "streak.updatedAt"
  }

  private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  /// Publishes the current streak and asks WidgetKit to redraw.
  static func write(days: Int, loggedToday: Bool) {
    guard let defaults else {
      // Only happens when the App Group capability isn't enabled on this target.
      print("⚠️ Streak snapshot skipped — App Group \(appGroup) unavailable")
      return
    }
    defaults.set(days, forKey: Key.days)
    defaults.set(loggedToday, forKey: Key.loggedToday)
    defaults.set(Date(), forKey: Key.updatedAt)
    WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
  }
}
