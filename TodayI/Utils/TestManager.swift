import Foundation
import SwiftData
import SwiftUI

enum SeedStrategy {
  case cycle
  case stableRandom
  case random
}

@MainActor
final class TestManager {
  // Shared helpers available to both
  fileprivate static func pickMood(for date: Date,
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
      return all.randomElement()!
    }
  }
  
  fileprivate static func randomPrompt(for mood: Mood) -> String {
    switch mood {
    case .happy:    return "Sunlight, coffee, and small wins. Felt really good today."
    case .sad:      return "A slow day. Letting myself feel it and breathe."
    case .neutral:  return "Steady and low-key. Nothing dramatic, just moving forward."
    case .disgust:  return "Ugh—something felt off. Hoping tomorrow is cleaner."
    case .angry:    return "Frustrations bubbled up. Journaling to cool down."
    case .surprise: return "Unexpected twist! Kinda exciting, honestly."
    case .fear:     return "A little anxious, but I handled what I could."
    }
  }
}

// MARK: - MemoryModel Debug Helpers
#if DEBUG
extension TestManager {
  @discardableResult
  static func seedMemories(
    on day: Date,
    in context: ModelContext,
    isPremium: Bool,
    username: String = "tester",
    userID: String = "debug-user",
    strategy: SeedStrategy = .random,
    replaceExisting: Bool = false
  ) throws -> [MemoryModel] {
    let cal  = Calendar.current
    let key  = cal.startOfDay(for: day)
    let next = cal.date(byAdding: .day, value: 1, to: key)!
    
    // Optionally clear existing
    var existing = try context.fetch(
      FetchDescriptor<MemoryModel>(
        predicate: #Predicate { $0.date >= key && $0.date < next }
      )
    )
    if replaceExisting {
      existing.forEach { context.delete($0) }
      existing.removeAll()
    }
    
    let count = isPremium ? Int.random(in: 2...5) : 1
    var newMemories: [MemoryModel] = []
    
    for idx in 0..<count {
      let mood = pickMood(for: key, index: idx, strategy: strategy, calendar: cal)
      let m = MemoryModel(
        id: UUID().uuidString,
        userID: userID,
        username: username,
        date: key,
        mood: mood,
        journalText: randomPrompt(for: mood),
        localImagePaths: [],
        remoteImagePaths: [],
        createdAt: Date(),
        updatedAt: Date()
      )
      context.insert(m)
      newMemories.append(m)
    }
    
    try upsertDateModel(for: key,
                        with: newMemories.map(\.mood),
                        in: context,
                        isPremium: isPremium)
    try context.save()
    return existing + newMemories
  }
  
  @discardableResult
  static func seedTodayMemories(
    in context: ModelContext,
    isPremium: Bool,
    username: String = "tester",
    userID: String = "debug-user",
    strategy: SeedStrategy = .random,
    replaceExisting: Bool = false
  ) throws -> [MemoryModel] {
    try seedMemories(on: Date(),
                     in: context,
                     isPremium: isPremium,
                     username: username,
                     userID: userID,
                     strategy: strategy,
                     replaceExisting: replaceExisting)
  }
  
  static func loadMemories(on day: Date,
                           in context: ModelContext,
                           isPremium: Bool) throws -> [MemoryModel] {
    let cal  = Calendar.current
    let key  = cal.startOfDay(for: day)
    let next = cal.date(byAdding: .day, value: 1, to: key)!
    
    let fetch = FetchDescriptor<MemoryModel>(
      predicate: #Predicate { $0.date >= key && $0.date < next },
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )
    let all = try context.fetch(fetch)
    return isPremium ? all : (all.last.map { [$0] } ?? [])
  }
}
#endif

// MARK: - DateModel Debug Helpers
#if DEBUG
extension TestManager {
  static func seedYear(_ year: Int,
                       in context: ModelContext,
                       strategy: SeedStrategy = .cycle) throws {
    let cal   = Calendar.current
    let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    let end   = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
    
    let existing = try context.fetch(
      FetchDescriptor<DateModel>(predicate: #Predicate { $0.date >= start && $0.date < end })
    )
    var byDate: [Date: DateModel] =
    Dictionary(uniqueKeysWithValues: existing.map { (cal.startOfDay(for: $0.date), $0) })
    
    var day = start
    var idx = 0
    while day < end {
      let key  = cal.startOfDay(for: day)
      let mood = pickMood(for: day, index: idx, strategy: strategy, calendar: cal)
      if let model = byDate[key] {
        model.moods = [mood]
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
    let cal   = Calendar.current
    let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    let end   = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
    let rows = try context.fetch(
      FetchDescriptor<DateModel>(predicate: #Predicate { $0.date >= start && $0.date < end })
    )
    rows.forEach { context.delete($0) }
    try context.save()
  }
  
  fileprivate static func upsertDateModel(for dayKey: Date,
                                          with newMoods: [Mood],
                                          in context: ModelContext,
                                          isPremium: Bool) throws {
    var dFetch = FetchDescriptor<DateModel>(predicate: #Predicate { $0.date == dayKey })
    dFetch.fetchLimit = 1
    let dateModel = try context.fetch(dFetch).first ?? DateModel(date: dayKey)
    if isPremium {
      dateModel.moods.append(contentsOf: newMoods)
    } else if let last = newMoods.last {
      dateModel.moods = [last]
    }
    if dateModel.modelContext == nil { context.insert(dateModel) }
  }
}
#endif
