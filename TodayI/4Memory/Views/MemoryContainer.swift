import SwiftUI
import SwiftData

/// Modal that displays all memories for a given calendar day.
struct MemoryContainer: View {
  let day: Date
  
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.swiftDataManager) private var swiftManager
  @Environment(\.colorScheme) private var scheme
  
  @State private var memories: [MemoryModel] = []
  @State private var isLoading = false
  @State private var errorText: String?
  
  // Keep the heavy formatter out of `body`
  private var titleText: String {
    day.formatted(.dateTime.weekday(.wide).month().day().year())
  }
  
  var body: some View {
    NavigationStack {
      contentView
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }
    .task {
      // Optional: show a spinner while we check/fetch
      await MainActor.run { isLoading = true; errorText = nil }
      
      do {
        let dayKey = day.formattedDayKeyLocal()   // make sure you have this helper
        
        // 1) Check if we already have at least one memory for that day (and user if available)
        var predicate = #Predicate<MemoryModel> { $0.dayKeyLocal == dayKey }
        if let uid = auth.userID {
          predicate = #Predicate<MemoryModel> { $0.dayKeyLocal == dayKey && $0.userID == uid }
        }
        
        var existsFetch = FetchDescriptor<MemoryModel>(predicate: predicate)
        existsFetch.fetchLimit = 1
        let existing = try context.fetch(existsFetch)
        
        // 2) If none locally, fetch from Firestore and import into SwiftData
        if existing.isEmpty, let uid = auth.userID {
          let dtos = try await MemoryService.fetchMemories(for: uid, dayKeyLocal: dayKey)
          try swiftManager?.importMemoriesIfNeeded(dtos)
        }
        
        // 3) Reload from SwiftData for display
        await load()
      } catch {
        await MainActor.run {
          self.errorText = error.localizedDescription
          self.isLoading = false
        }
      }
    }
    .onChange(of: entitlements.isPremium) { _, _ in
      Task { await load() }
    }
  }
}

// MARK: - View pieces
private extension MemoryContainer {
  @ViewBuilder
  var contentView: some View {
    if isLoading {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let errorText {
      ContentUnavailableView(
        "Couldn’t load memories",
        systemImage: "exclamationmark.triangle",
        description: Text(errorText)
      )
    } else if memories.isEmpty {
      ContentUnavailableView(
        "No memories",
        systemImage: "book.closed",
        description: Text(day.formatted(date: .abbreviated, time: .omitted))
      )
    } else {
      List {
        ForEach(memories, id: \.id) { mem in
          MemoryRow(memory: mem, isPremium: entitlements.isPremium)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .listRowInsets(EdgeInsets())// remove List’s insets
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
      }
      .contentMargins(.horizontal, 0, for: .scrollContent)
      .listStyle(.plain)
      .refreshable { await load() }
    }
  }
  
  @ToolbarContentBuilder
  var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Button { dismiss() } label: { Image(systemName: "xmark") }
    }
    ToolbarItem(placement: .topBarTrailing) {
      Menu {
        Button("Clear memories for this day", role: .destructive) {
          Task {
            do {
              try await clearThisDay()
              await load()
            } catch {
              self.errorText = error.localizedDescription
            }
          }
        }
      } label: { Image(systemName: "ellipsis.circle") }
    }
  }
}

// MARK: - Data
private extension MemoryContainer {
  func load() async {
    await MainActor.run {
      isLoading = true
      errorText = nil
    }
    do {
      // ✅ Use viewer's local timezone for day bounds
      var cal = Calendar(identifier: .gregorian)
      cal.timeZone = .current
      let start = cal.startOfDay(for: day)
      let end   = cal.date(byAdding: .day, value: 1, to: start)!
      
      // Base predicate: rows whose saved "author-local midnight instant" falls in [start, end)
      var predicate = #Predicate<MemoryModel> { $0.date >= start && $0.date < end }
      if let uid = auth.userID {
        predicate = #Predicate<MemoryModel> { $0.userID == uid && $0.date >= start && $0.date < end }
      }
      
      var fetch = FetchDescriptor<MemoryModel>(predicate: predicate)
      
      if entitlements.isPremium {
        // Premium: show all (oldest → newest, or flip if you prefer)
        fetch.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
      } else {
        // Free: only the latest
        fetch.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        fetch.fetchLimit = 1
      }
      
      // (optional) quick debug
      // print("🔎 Query day range:", start, "→", end, "uid:", auth.userID ?? "nil", "premium:", entitlements.isPremium)
      
      let items = try context.fetch(fetch)
      
      await MainActor.run {
        self.memories = items
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.errorText = error.localizedDescription
        self.isLoading = false
      }
    }
  }
  
  func clearThisDay() async throws {
    // ✅ Same day-bound math as in load()
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let start = cal.startOfDay(for: day)
    let end   = cal.date(byAdding: .day, value: 1, to: start)!
    
    let fetch = FetchDescriptor<MemoryModel>(
      predicate: #Predicate { $0.date >= start && $0.date < end }
    )
    let rows = try context.fetch(fetch)
    rows.forEach { context.delete($0) }
    try context.save()
  }
}
