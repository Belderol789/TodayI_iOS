import SwiftData
import Foundation

extension SwiftDataManager {
  /// Fetch all `DateModel` rows whose `date` falls within [start ... end).
  func fetchDateModels(from start: Date, to endExclusive: Date) throws -> [DateModel] {
    let descriptor = FetchDescriptor<DateModel>(
      predicate: #Predicate { $0.date >= start && $0.date < endExclusive },
      sortBy: [SortDescriptor(\.date, order: .forward)]
    )
    return try context.fetch(descriptor)
  }
  
  /// Convenience: fetch all `DateModel` rows for a specific Gregorian year
  /// using the provided timezone (defaults to current).
  func fetchDateModels(inYear year: Int,
                       calendar: Calendar = Calendar(identifier: .gregorian),
                       timeZone: TimeZone = .current) throws -> [DateModel] {
    var cal = calendar
    cal.timeZone = timeZone
    let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    let end   = cal.date(byAdding: .year, value: 1, to: start)!
    return try fetchDateModels(from: start, to: end)
  }
  
  func importDatesIfNeeded(_ dtos: [DateDTO]) throws {
    for dto in dtos {
      let fetch = FetchDescriptor<DateModel>(
        predicate: #Predicate { $0.date == dto.date }
      )
      let moods = dto.moodRaws.compactMap { Mood(rawValue: $0) }

      if let existing = try context.fetch(fetch).first {
        // Refresh moods rather than skipping — a day can gain a mood after it was
        // first stored (a second memory, or one posted from another device).
        if existing.moods.map(\.rawValue) != moods.map(\.rawValue) {
          existing.moods = moods
        }
      } else {
        context.insert(DateModel(date: dto.date, moods: moods))
      }
    }
    try context.save()
  }
}

// MARK: - Date sync scheduling
extension SwiftDataManager {
  /// Dates are pulled from Firestore once per app launch.
  ///
  /// This used to be once per *install*: the callers guarded on "do we have any
  /// DateModel at all", so as soon as a single day was stored the calendar never
  /// pulled again. Any day created while the local store was unavailable — or on
  /// another device — stayed invisible, with pull-to-refresh the only way back.
  /// One `fetchDates` query per launch is the cost of that being self-healing.
  private static var datesSyncedThisLaunch = false

  var needsDateSync: Bool { !Self.datesSyncedThisLaunch }

  func markDatesSynced() { Self.datesSyncedThisLaunch = true }

  // MARK: - Delta cursor
  //
  // `fetchDates` used to pull every `dates/{dayKey}` document, every launch, forever —
  // at a year of history that's ~89% of the app's total reads for a cost that only ever
  // grows. The cursor below turns each launch's one allowed fetch into a delta: only
  // days touched since the last successful sync. Keyed per uid so switching accounts on
  // one device — or a fresh account after a delete — can't reuse a stranger's cursor and
  // silently miss its own first full sync.

  private static func cursorKey(for uid: String) -> String { "datesSyncCursor_\(uid)" }

  /// `nil` means "never synced" — callers should do a full fetch.
  func datesSyncCursor(for uid: String) -> Date? {
    let raw = UserDefaults.standard.double(forKey: Self.cursorKey(for: uid))
    return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
  }

  /// Callers pass the moment *just before* the query ran, not `Date()` afterward — a
  /// write that lands mid-request is then still `>` the stored cursor and gets picked up
  /// next launch, rather than being silently skipped forever.
  func setDatesSyncCursor(_ date: Date, for uid: String) {
    UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.cursorKey(for: uid))
  }
}
