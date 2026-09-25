//
//  SwiftData_DebugSeed.swift
//  TodayI
//

#if DEBUG
import Foundation
import SwiftData

/// Local-only fixtures for the surfaces that otherwise need you to wait for a
/// specific day — the streak pill, the widget, and the "at risk" state that only
/// exists between midnight and your next entry.
///
/// Writes `DateModel` rows only: those are what the streak counts, they're derived
/// from Firestore rather than authoritative, and nothing here touches the network or
/// creates memories. Compiled out of release entirely.
extension SwiftDataManager {

  /// Marks the last `count` days as journaled.
  /// - Parameter includingToday: false leaves today blank, which is the "streak alive
  ///   but at risk" state — the one that's normally only reachable before you post.
  func debugSeedStreak(count: Int, includingToday: Bool) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let today = cal.startOfDay(for: Date())
    let firstOffset = includingToday ? 0 : 1

    for offset in firstOffset ..< (firstOffset + count) {
      guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
      debugUpsertDay(day)
    }

    try? context.save()
    refreshStreakSnapshot()
    NotificationCenter.default.post(name: .memoryDidChangeLocally, object: nil)
    print("🧪 Seeded \(count) day(s), includingToday: \(includingToday)")
  }

  /// Removes every locally cached mood day. Real data is recoverable — `DateModel`
  /// is a cache of `users/{uid}/dates`, so pull-to-refresh on Calendar re-syncs it.
  func debugClearMoodDays() {
    let rows = (try? context.fetch(FetchDescriptor<DateModel>())) ?? []
    rows.forEach { context.delete($0) }
    try? context.save()
    refreshStreakSnapshot()
    NotificationCenter.default.post(name: .memoryDidChangeLocally, object: nil)
    print("🧪 Cleared \(rows.count) local mood day(s)")
  }

  /// Leaves a day alone if it already exists, so seeding can't overwrite real moods.
  private func debugUpsertDay(_ day: Date) {
    let fetch = FetchDescriptor<DateModel>(predicate: #Predicate { $0.date == day })
    guard ((try? context.fetch(fetch))?.first) == nil else { return }
    context.insert(DateModel(date: day, moods: [.happy]))
  }
}
#endif
