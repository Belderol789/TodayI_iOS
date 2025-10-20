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
      if try context.fetch(fetch).isEmpty {
        let moods = dto.moodRaws.compactMap { Mood(rawValue: $0) }
        let model = DateModel(date: dto.date, moods: moods)
        context.insert(model)
      }
    }
    try context.save()
  }
  
}
