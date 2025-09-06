import SwiftData
import Foundation

@MainActor
final class SwiftDataManager {
  private let context: ModelContext
  private let store: EntitlementStore   // check free vs premium
  
  init(context: ModelContext, store: EntitlementStore) {
    self.context = context
    self.store = store
  }
  
  // MARK: - Memory
  /// Save a MemoryModel and sync its DateModel
  func saveMemory(_ memory: MemoryModel) throws {
    let cal = Calendar.current
    let key = cal.startOfDay(for: memory.date)
    
    // Insert memory
    context.insert(memory)
    
    // Fetch or create DateModel
    let fetch = FetchDescriptor<DateModel>(
      predicate: #Predicate { $0.date == key }
    )
    let dateModel = try context.fetch(fetch).first ?? DateModel(date: key)
    
    if store.isPremium {
      // Premium: append all moods from memories
      var moods = dateModel.moods
      moods.append(memory.mood)
      dateModel.moods = moods
    } else {
      // Free: only keep the latest mood
      dateModel.moods = [memory.mood]
    }
    
    // Insert DateModel if it’s new
    if dateModel.modelContext == nil {
      context.insert(dateModel)
    }
    
    // Save everything
    try context.save()
  }
}

extension SwiftDataManager {
  /// Load memories for a given date.
  /// Premium => all; Free => only the latest
  func loadMemories(for date: Date) throws -> [MemoryModel] {
    let cal = Calendar.current
    let key = cal.startOfDay(for: date)
    
    let fetch = FetchDescriptor<MemoryModel>(
      predicate: #Predicate { $0.date == key },
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )
    
    let rows = try context.fetch(fetch)
    return store.isPremium ? rows : (rows.last.map { [$0] } ?? [])
  }
}
