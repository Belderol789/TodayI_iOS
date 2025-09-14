import SwiftUI
import SwiftData

/// Modal that displays all memories for a given calendar day.
struct MemoryContainer: View {
  let day: Date
  
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var auth: AuthStore
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
    .task { await load() }
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
      ScrollView {
        LazyVStack(spacing: 16) {
          ForEach(memories) { mem in
            MemoryRow(
              memory: mem,
              isPremium: entitlements.isPremium
            )
            .padding(.horizontal, 16)
          }
        }
        .padding(.vertical, 16)
      }
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
      let cal  = Calendar.current
      let key  = cal.startOfDay(for: day)
      let next = cal.date(byAdding: .day, value: 1, to: key)!
      
      // Base predicate: this day (optionally scope to current user)
      var predicate = #Predicate<MemoryModel> { $0.date >= key && $0.date < next }
      if let uid = auth.userID {
        predicate = #Predicate<MemoryModel> { $0.date >= key && $0.date < next && $0.userID == uid }
      }
      
      var fetch = FetchDescriptor<MemoryModel>(predicate: predicate)
      
      if entitlements.isPremium {
        // Premium: show all (oldest → newest or whichever you prefer)
        fetch.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
      } else {
        // Free: only the latest (newest first, limit 1)
        fetch.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        fetch.fetchLimit = 1
      }
      
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
    let cal  = Calendar.current
    let key  = cal.startOfDay(for: day)
    let next = cal.date(byAdding: .day, value: 1, to: key)!
    let fetch = FetchDescriptor<MemoryModel>(
      predicate: #Predicate { $0.date >= key && $0.date < next }
    )
    let rows = try context.fetch(fetch)
    rows.forEach { context.delete($0) }
    try context.save()
  }
}
