//
//  StreakSnapshot.swift
//  TodayI
//
//  App-side writer. The widget has its own copy of this contract — see
//  TodayIWidget/StreakSnapshotReader.swift. Keep the suite name and keys identical.
//

import Foundation
import UIKit
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

    // World mood. Colours are published as resolved hex for light and dark rather
    // than a mood name, so the widget renders what it's given and never needs its
    // own copy of the palette — `Mood.adaptiveColor` stays the single source.
    static let worldMood = "world.mood"
    static let worldMoodLightHex = "world.moodLightHex"
    static let worldMoodDarkHex = "world.moodDarkHex"
    static let worldPercent = "world.percent"
    static let worldTotal = "world.total"
    static let worldUpdatedAt = "world.updatedAt"
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

  /// Publishes how the world feels today.
  ///
  /// The widget can't read Firestore — it has no Firebase and a tight memory budget —
  /// so the app hands it the already-fetched tally. That means the value is only as
  /// fresh as the last World feed load (once per launch, or a pull-to-refresh);
  /// `worldUpdatedAt` is published so the widget can decline to show something stale.
  static func writeWorldMood(_ mood: Mood?, percent: Int, total: Int) {
    guard let defaults else { return }

    guard let mood, total > 0 else {
      [Key.worldMood, Key.worldMoodLightHex, Key.worldMoodDarkHex,
       Key.worldPercent, Key.worldTotal, Key.worldUpdatedAt]
        .forEach(defaults.removeObject(forKey:))
      WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
      return
    }

    let ui = UIColor(mood.adaptiveColor)
    defaults.set(mood.rawValue, forKey: Key.worldMood)
    defaults.set(ui.hexString(for: .light), forKey: Key.worldMoodLightHex)
    defaults.set(ui.hexString(for: .dark), forKey: Key.worldMoodDarkHex)
    defaults.set(percent, forKey: Key.worldPercent)
    defaults.set(total, forKey: Key.worldTotal)
    defaults.set(Date(), forKey: Key.worldUpdatedAt)
    WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
  }
}

private extension UIColor {
  /// Resolves a dynamic colour against one appearance and returns "RRGGBB".
  func hexString(for style: UIUserInterfaceStyle) -> String {
    let resolved = resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
    let clamp = { (v: CGFloat) in Int((max(0, min(1, v)) * 255).rounded()) }
    return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
  }
}
