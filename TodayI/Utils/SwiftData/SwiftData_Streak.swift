//
//  SwiftData_Streak.swift
//  TodayI
//

import Foundation
import SwiftData

/// How many consecutive days the user has journaled, and whether today counts yet.
struct StreakInfo: Equatable {
  let days: Int
  /// False while the streak is alive but today is still unwritten — the "at risk"
  /// state that gives the pill its nudge.
  let loggedToday: Bool

  static let none = StreakInfo(days: 0, loggedToday: false)

  var isAtRisk: Bool { days > 0 && !loggedToday }
}

extension SwiftDataManager {
  /// Counts back from today over `DateModel`, which holds one row per day the user
  /// recorded a mood. That table is written on every local save and refilled from
  /// Firestore once per launch, so the streak costs no reads and survives a reinstall.
  ///
  /// A day missing from the middle breaks the run. Today being missing does **not** —
  /// the day isn't over, so the streak stays alive (and `loggedToday` is false) until
  /// midnight passes without an entry, exactly like Duolingo.
  func currentStreak(asOf now: Date = Date(), in tz: TimeZone = .current) -> StreakInfo {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz

    guard let rows = try? context.fetch(FetchDescriptor<DateModel>()), !rows.isEmpty else {
      return .none
    }

    // Normalise to local midnights so rows written in another timezone still line up.
    let journaled = Set(rows.map { cal.startOfDay(for: $0.date) })
    let today = cal.startOfDay(for: now)
    let loggedToday = journaled.contains(today)

    // Start at today if it's written, otherwise yesterday — a streak isn't broken
    // just because the user hasn't got to today yet.
    guard var cursor = loggedToday ? today : cal.date(byAdding: .day, value: -1, to: today),
          journaled.contains(cursor)
    else {
      return StreakInfo(days: 0, loggedToday: loggedToday)
    }

    var count = 0
    while journaled.contains(cursor) {
      count += 1
      guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
      cursor = previous
    }

    return StreakInfo(days: count, loggedToday: loggedToday)
  }
}
