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

// MARK: - Sample year (App Store screenshots)

/// SplitMix64. `SystemRandomNumberGenerator` can't be seeded, and a sample that changes
/// every run can't produce a consistent screenshot set.
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E3779B97F4A7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
  }
}

/// A lived-in year for screenshots: memories and mood days from January 1 to today.
///
/// Safe against production by construction. Memories are written with
/// `needsCloudBackup = false` and `isPublic = false`, so neither `CloudBackupService`
/// nor the feed ever sees them, and nothing here calls Firebase. Days that already have
/// real moods are skipped, and every id and date written is remembered, so turning the
/// sample off removes exactly what it added.
extension SwiftDataManager {

  static let sampleIDPrefix = "debug-sample-"
  private static let sampleDaysKey = "debug.sampleYear.days"

  var hasSampleYear: Bool {
    !(UserDefaults.standard.array(forKey: Self.sampleDaysKey) ?? []).isEmpty
  }

  func debugSeedSampleYear(userID: String, username: String, isPremium: Bool) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let today = cal.startOfDay(for: Date())
    guard let jan1 = cal.date(from: cal.dateComponents([.year], from: today)) else { return }
    let dayCount = (cal.dateComponents([.day], from: jan1, to: today).day ?? 0) + 1

    // Fixed seed: every run produces the same year, so a retaken screenshot matches
    // the rest of the set instead of telling a different story each time.
    var rng = SeededGenerator(seed: 2026)
    var seededDays: [Double] = []

    for offset in 0 ..< dayCount {
      guard let day = cal.date(byAdding: .day, value: offset, to: jan1) else { continue }
      let daysAgo = dayCount - 1 - offset
      // The last seven weeks are unbroken so the streak pill has something to show;
      // before that, roughly one day in eight is skipped, the way a real year looks.
      if daysAgo > 48, Int.random(in: 0 ..< 8, using: &rng) == 0 { continue }

      let existing = FetchDescriptor<DateModel>(predicate: #Predicate { $0.date == day })
      guard ((try? context.fetch(existing))?.first) == nil else { continue }

      // About one day in six gets a second entry, as Premium allows. Today gets exactly
      // one, always the same warm one: it's the card at the top of the Home screenshot.
      let isToday = daysAgo == 0
      let entryCount = !isToday && Int.random(in: 0 ..< 6, using: &rng) == 0 ? 2 : 1
      var moods: [Mood] = []
      for index in 0 ..< entryCount {
        let mood = isToday ? .happy : Self.sampleMood(using: &rng)
        moods.append(mood)
        // Today's entry lands before 9:41, the screenshots' status-bar time.
        let hour = isToday ? 8
          : index == 0 ? Int.random(in: 8 ... 13, using: &rng)
                       : Int.random(in: 17 ... 22, using: &rng)
        let created = cal.date(bySettingHour: hour,
                               minute: Int.random(in: 0 ... 59, using: &rng),
                               second: 0, of: day) ?? day
        let memory = MemoryModel(
          id: Self.sampleIDPrefix + UUID().uuidString,
          userID: userID,
          username: username,
          date: day,
          mood: mood,
          journalText: isToday
            ? "Called my sister and we laughed for an hour."
            : Self.sampleLines[mood]?.randomElement(using: &rng) ?? "",
          likes: 0,
          isPublic: false,
          isPremium: isPremium,
          createdAt: created,
          updatedAt: created
        )
        memory.needsCloudBackup = false
        context.insert(memory)
      }
      context.insert(DateModel(date: day, moods: moods))
      seededDays.append(day.timeIntervalSince1970)
    }

    try? context.save()
    UserDefaults.standard.set(seededDays, forKey: Self.sampleDaysKey)
    refreshStreakSnapshot()
    NotificationCenter.default.post(name: .memoryDidChangeLocally, object: nil)
    print("🧪 Seeded a sample year: \(seededDays.count) day(s)")
  }

  func debugClearSampleYear() {
    let prefix = Self.sampleIDPrefix
    let memories = (try? context.fetch(FetchDescriptor<MemoryModel>(
      predicate: #Predicate { $0.id.starts(with: prefix) }))) ?? []
    memories.forEach { context.delete($0) }

    let days = (UserDefaults.standard.array(forKey: Self.sampleDaysKey) as? [Double] ?? [])
      .map(Date.init(timeIntervalSince1970:))
    for day in days {
      let fetch = FetchDescriptor<DateModel>(predicate: #Predicate { $0.date == day })
      (try? context.fetch(fetch))?.forEach { context.delete($0) }
    }

    try? context.save()
    UserDefaults.standard.removeObject(forKey: Self.sampleDaysKey)
    refreshStreakSnapshot()
    NotificationCenter.default.post(name: .memoryDidChangeLocally, object: nil)
    print("🧪 Cleared the sample year: \(memories.count) memories, \(days.count) day(s)")
  }

  /// Weighted so the year reads as a believable mix rather than an even rainbow.
  private static func sampleMood(using rng: inout SeededGenerator) -> Mood {
    let weighted: [(Mood, Int)] = [(.happy, 34), (.neutral, 18), (.surprise, 12), (.sad, 12),
                                   (.disgust, 9), (.angry, 9), (.fear, 8)]
    var roll = Int.random(in: 0 ..< weighted.reduce(0) { $0 + $1.1 }, using: &rng)
    for (mood, weight) in weighted {
      if roll < weight { return mood }
      roll -= weight
    }
    return .neutral
  }

  private static let sampleLines: [Mood: [String]] = [
    .happy: [
      "Finally finished the book I've been carrying around for a month.",
      "Lunch outside with the team. Sun was out the whole time.",
      "Called my sister and we laughed for an hour.",
      "Morning run felt easy for once.",
      "Got good news at work and celebrated with ice cream.",
    ],
    .neutral: [
      "Quiet day. Laundry, groceries, an early night.",
      "Work, gym, dinner. Nothing to report and that's fine.",
      "Rain all afternoon, so I stayed in and read.",
      "Long commute, podcast helped.",
    ],
    .surprise: [
      "Bumped into a friend I hadn't seen since school.",
      "The new café on the corner is actually great.",
      "Didn't expect the presentation to go that well.",
      "A package arrived I'd completely forgotten ordering.",
    ],
    .sad: [
      "Missing home today.",
      "Plans fell through and the evening felt long.",
      "Tired in a way sleep doesn't fix.",
      "Said goodbye to a coworker who's moving away.",
    ],
    .disgust: [
      "Someone microwaved fish in the office again.",
      "Stepped in a puddle with new shoes on.",
      "The traffic this morning was unreal.",
    ],
    .angry: [
      "Waited an hour for a delivery that never came.",
      "Third time this week the train was late.",
      "Got talked over in a meeting, again.",
    ],
    .fear: [
      "Big interview tomorrow. Trying not to overthink it.",
      "Doctor's appointment next week and I keep thinking about it.",
      "First day at the new gym. Nervous for no reason.",
    ],
  ]
}
#endif
