import Foundation
import SwiftData
import SwiftUI

enum SeedStrategy {
  case cycle
  case stableRandom
  case random
  case sadOctober
}

@MainActor
final class TestManager {
  // Shared helpers available to both
  fileprivate static func pickMood(
    for date: Date,
    index: Int,
    strategy: SeedStrategy,
    calendar: Calendar
  ) -> Mood {
    
    func weightedPick(_ weights: [(Mood, Int)]) -> Mood {
      let total = weights.reduce(0) { $0 + $1.1 }
      var roll = Int.random(in: 1...max(total, 1))
      for (mood, w) in weights {
        roll -= w
        if roll <= 0 { return mood }
      }
      return weights.first?.0 ?? .neutral
    }
    
    switch strategy {
    case .cycle:
      return Mood.allCases[index % Mood.allCases.count]
      
    case .stableRandom:
      let ord = calendar.ordinality(of: .day, in: .year, for: date) ?? index
      return Mood.allCases[(ord - 1) % Mood.allCases.count]
      
    case .random:
      return Mood.allCases.randomElement()!
      
    case .sadOctober:
      let month = calendar.component(.month, from: date)
      
      // Baseline: mostly believable everyday moods
      var base: [(Mood, Int)] = [
        (.neutral, 38),
        (.happy,   22),
        (.sad,     20),
        (.angry,   12),
        (.surprise, 4),
        (.fear,     3),
        (.disgust,  1)
      ]
      
      // October: tilt sad + neutral a bit, but keep variety
      if month == 10 {
        base = [
          (.neutral, 40),
          (.sad,     60),
          (.angry,   12)
        ]
      }
      
      if month == 11 {
        base = [
          (.neutral, 50),
          (.sad,     30),
          (.happy,   12),
          (.angry,   12),
          (.surprise, 3),
          (.fear,     2),
          (.disgust,  1)
        ]
      }
      
      if month == 12 {
        base = [
          (.neutral, 50),
          (.sad,     30),
          (.happy,   12),
          (.angry,   12),
          (.surprise, 3),
          (.fear,     2),
          (.disgust,  1)
        ]
      }
      
      return weightedPick(base)
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
  
  // Seeds (optionally clears) and returns DateModels for the whole year.
  static func loadYearModels(
    _ year: Int,
    in context: ModelContext,
    strategy: SeedStrategy = .cycle,
    replaceExisting: Bool = false
  ) throws -> [DateModel] {
    
    if replaceExisting {
      try clearYear(year, in: context)
    }
    
    try seedYear(year, in: context, strategy: strategy)
    
    let cal = Calendar.current
    let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    let end   = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
    
    let fd = FetchDescriptor<DateModel>(
      predicate: #Predicate { $0.date >= start && $0.date < end },
      sortBy: [SortDescriptor(\.date, order: .forward)]
    )
    let rows = try context.fetch(fd)
    rows.forEach { _ = $0.moodRaws }   // ✅ materialize
    return rows
  }
  
  
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
        likes: 100,
        localImageNames: [],
        remoteImagePaths: [],
        isPremium: isPremium,
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
  static func seedYear(
    _ year: Int,
    in context: ModelContext,
    strategy: SeedStrategy = .cycle
  ) throws {
    let cal = Calendar.current
    
    let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    
    // 👇 Cap at today if this is the current year
    let today = cal.startOfDay(for: Date())
    let yearEnd = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
    let end = (year == cal.component(.year, from: today)) ? min(today, yearEnd) : yearEnd
    
    let existing = try context.fetch(
      FetchDescriptor<DateModel>(
        predicate: #Predicate { $0.date >= start && $0.date < end }
      )
    )
    
    var byDate: [Date: DateModel] =
    Dictionary(uniqueKeysWithValues: existing.map {
      (cal.startOfDay(for: $0.date), $0)
    })
    
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

@MainActor
enum TestDataFactory {
  
  // MARK: - Date Models (Calendar / History)
  
  static func makeYearDateModels(
    year: Int,
    strategy: SeedStrategy = .cycle,
    calendar: Calendar = .current
  ) -> [DateModel] {
    
    let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
    let today = calendar.startOfDay(for: Date())
    let yearEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
    let end = (year == calendar.component(.year, from: today)) ? min(today, yearEnd) : yearEnd
    
    var models: [DateModel] = []
    var day = start
    var idx = 0
    
    while day < end {
      let key = calendar.startOfDay(for: day)
      let mood = TestManager.pickMood(
        for: key,
        index: idx,
        strategy: strategy,
        calendar: calendar
      )
      
      models.append(
        DateModel(
          date: key,
          moods: [mood]
        )
      )
      
      idx += 1
      day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    
    return models.sorted { $0.date < $1.date }
  }
  
  // MARK: - Memories (Daily Detail / Feed)
  
  static func makeMemories(
    for day: Date,
    isPremium: Bool,
    username: String = "tester",
    userID: String = "debug-user",
    strategy: SeedStrategy = .random,
    calendar: Calendar = .current
  ) -> [MemoryModel] {
    
    let key = calendar.startOfDay(for: day)
    let count = isPremium ? Int.random(in: 2...5) : 1
    
    return (0..<count).map { idx in
      let mood = TestManager.pickMood(
        for: key,
        index: idx,
        strategy: strategy,
        calendar: calendar
      )
      
      return MemoryModel(
        id: UUID().uuidString,
        userID: userID,
        username: username,
        date: key,
        mood: mood,
        journalText: TestManager.randomPrompt(for: mood),
        likes: 100,
        localImageNames: [],
        remoteImagePaths: [],
        isPremium: isPremium,
        createdAt: Date(),
        updatedAt: Date()
      )
    }
  }
  
  static func makeTodayMemories(
    isPremium: Bool,
    username: String = "tester",
    userID: String = "debug-user",
    strategy: SeedStrategy = .random
  ) -> [MemoryModel] {
    makeMemories(
      for: Date(),
      isPremium: isPremium,
      username: username,
      userID: userID,
      strategy: strategy
    )
  }
  
  /// Generates a "global feed" style list: many posts across multiple days and users.
  static func makeGlobalFeedMemories(
    for day: Date,
    count: Int = 24,
    daysBack: Int = 7,
    userCount: Int = 8,
    isPremium: Bool = true,
    strategy: SeedStrategy = .stableRandom,
    calendar: Calendar = .current
  ) -> [MemoryModel] {
    
    let dayKey = calendar.startOfDay(for: day)
    var results: [MemoryModel] = []
    results.reserveCapacity(count)
    
    for i in 0..<count {
      let offsetDays = i % max(daysBack, 1)
      let postDay = calendar.date(byAdding: .day, value: -offsetDays, to: dayKey) ?? dayKey
      
      let u = i % max(userCount, 1)
      let username = "user\(u + 1)"
      let userID = "debug-user-\(u + 1)"
      
      // Generate a few memories for that day, then pick one to simulate a feed post
      let candidates = makeMemories(
        for: postDay,
        isPremium: isPremium,
        username: username,
        userID: userID,
        strategy: strategy,
        calendar: calendar
      )
      
      if let chosen = candidates.randomElement() {
        // Make timestamps feel like a feed (newer posts are more recent)
        let minutesAgo = i * Int.random(in: 3...12)
        chosen.createdAt = Date().addingTimeInterval(TimeInterval(-minutesAgo * 60))
        chosen.updatedAt = chosen.createdAt
        
        results.append(chosen)
      }
    }
    
    // Newest first
    return results.sorted { $0.createdAt > $1.createdAt }
  }
  
}
