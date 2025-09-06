import SwiftUI
import SwiftData

struct MemoryView: View {
  let date: Date
  
  @Environment(\.modelContext) private var context
  @EnvironmentObject var store: EntitlementStore
  
  @State private var memories: [MemoryModel] = []
  @State private var isLoading = false
  @State private var errorText: String?
  
  private var title: String {
    let df = DateFormatter()
    df.dateStyle = .full
    return df.string(from: date)
  }
  
  var body: some View {
    Group {
      if isLoading {
        ProgressView("Loading…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let errorText {
        ContentUnavailableView("Couldn’t load memories",
                               systemImage: "exclamationmark.triangle",
                               description: Text(errorText))
      } else if memories.isEmpty {
        ContentUnavailableView("No memories for this day",
                               systemImage: "text.book.closed",
                               description: Text("Add one to get started."))
      } else {
        List {
          ForEach(memories, id: \.id) { mem in
//            MemoryRow(memory: mem, isPremium: store.isPremium)
//              .listRowSeparator(.hidden)
//              .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
          }
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .task(id: date) { await load() }           // reload if the date changes
    .refreshable { await load() }              // pull-to-refresh, optional
  }
  
  @MainActor
  private func load() async {
    isLoading = true
    errorText = nil
    do {
      let manager = SwiftDataManager(context: context, store: store)
      let rows = try manager.loadMemories(for: date)
      memories = rows
      isLoading = false
    } catch {
      isLoading = false
      errorText = error.localizedDescription
    }
  }
}
