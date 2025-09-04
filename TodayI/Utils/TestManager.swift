import Foundation
import SwiftData
import SwiftUI

enum SeedStrategy {
  case cycle
  case stableRandom
  case random          // <- new
}

@MainActor
final class TestManager {
  static func seedYear(_ year: Int,
                       in context: ModelContext,
                       strategy: SeedStrategy = .cycle) throws
  {
let cal = Calendar.current
let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
let end   = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!

// fetch existing once
let existing = try context.fetch(
  FetchDescriptor<DateModel>(predicate: #Predicate { $0.date >= start && $0.date < end })
)

var byDate: [Date: DateModel] = Dictionary(
  uniqueKeysWithValues: existing.map { (cal.startOfDay(for: $0.date), $0) }
)

var day = start
var idx = 0
while day < end {
  let key = cal.startOfDay(for: day)
  let mood = pickMood(for: day, index: idx, strategy: strategy, calendar: cal)
  
  if let model = byDate[key] {
    model.moods = [mood]  // updates moodRaws via your @Transient setter
  } else {
    let model = DateModel(date: key, moods: [mood])
    context.insert(model)
    byDate[key] = model
  }
  
  idx += 1
  day = cal.date(byAdding: .day, value: 1, to: day)!
}

try context.save()
  }
  
  static func clearYear(_ year: Int, in context: ModelContext) throws {
    let cal = Calendar.current
    let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    let end   = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
    let rows = try context.fetch(
      FetchDescriptor<DateModel>(predicate: #Predicate { $0.date >= start && $0.date < end })
    )
    rows.forEach { context.delete($0) }
    try context.save()
  }
  
  private static func pickMood(for date: Date,
                               index: Int,
                               strategy: SeedStrategy,
                               calendar: Calendar) -> Mood {
    let all = Mood.allCases
    switch strategy {
    case .cycle:
      return all[index % all.count]
    case .stableRandom:
      let ord = calendar.ordinality(of: .day, in: .year, for: date) ?? index
      return all[(ord - 1) % all.count]
    case .random:
      return all.randomElement()!        // true random every run
    }
  }
}
