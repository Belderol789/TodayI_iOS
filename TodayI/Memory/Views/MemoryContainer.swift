import SwiftUI
import SwiftData

/// Modal that displays all memories for a given calendar day.
struct MemoryContainer: View {
  let day: Date
  
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var entitlements: EntitlementStore
  @Environment(\.colorScheme) private var scheme
  
  @State private var memories: [MemoryModel] = []
  @State private var isLoading = false
  @State private var errorText: String?
  
  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorText {
          ContentUnavailableView("Couldn’t load memories",
                                 systemImage: "exclamationmark.triangle",
                                 description: Text(errorText))
        } else if memories.isEmpty {
          ContentUnavailableView("No memories",
                                 systemImage: "book.closed",
                                 description: Text(day.formatted(date: .abbreviated, time: .omitted)))
        } else {
          ScrollView {
            LazyVStack(spacing: 16) {
              ForEach(memories) { mem in
                MemoryRow(memory: mem,
                          isPremium: entitlements.isPremium)
                .environmentObject(entitlements)
                .padding(.horizontal, 16)
              }
            }
            .padding(.vertical, 16)
          }
          .refreshable { await load() }
        }
      }
      .navigationTitle(day.formatted(.dateTime.weekday(.wide).month().day().year()))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button { dismiss() } label: { Image(systemName: "xmark") }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Seed random for this day") {
              Task {
                do {
                  _ = try TestManager.seedMemories(
                    on: day,
                    in: context,
                    isPremium: entitlements.isPremium,
                    username: "demo",
                    userID: "demo-user",
                    strategy: .random,
                    replaceExisting: false   // set true if you want to overwrite
                  )
                  await load()
                } catch { self.errorText = error.localizedDescription }
              }
            }
            
            Button("Clear memories for this day", role: .destructive) {
              Task {
                do {
                  try await clearThisDay()
                  await load()
                } catch { self.errorText = error.localizedDescription }
              }
            }
          } label: { Image(systemName: "ellipsis.circle") }
        }
      }
    }
    .task { await load() }
    .onChange(of: entitlements.isPremium) { _, _ in
      Task { await load() }
    }
  }
  
  // MARK: - Data
  
  private func clearThisDay() async throws {
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
  
  private func load() async {
    await MainActor.run {
      isLoading = true
      errorText = nil
    }
    do {
      let items = try TestManager.loadMemories(on: day,
                                               in: context,
                                               isPremium: entitlements.isPremium)
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
}
