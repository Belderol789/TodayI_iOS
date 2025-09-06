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
        Button("Seed random for this day") {
          Task {
            do {
              try await seedForThisDay()
              await load()
            } catch {
              self.errorText = error.localizedDescription
            }
          }
        }
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
      let items = try TestManager.loadMemories(
        on: day,
        in: context,
        isPremium: entitlements.isPremium
      )
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
  
  func seedForThisDay() async throws {
    // Require a logged-in user (so the row is "yours")
    guard let userID = auth.userID else {
      throw NSError(domain: "MemoryContainer", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "No logged-in user."
      ])
    }
    let username = auth.username ?? "Me"
    
    _ = try TestManager.seedMemories(
      on: day,
      in: context,
      isPremium: entitlements.isPremium,
      username: username,
      userID: userID,
      strategy: .random,
      replaceExisting: false
    )
  }
}
