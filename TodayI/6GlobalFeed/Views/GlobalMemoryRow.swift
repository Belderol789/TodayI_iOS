import SwiftUI

struct GlobalMemoryRow: View {
  let dto: MemoryDTO
  @Environment(\.modelContext) private var context
  
  @State private var model: MemoryModel?
  
  var body: some View {
    Group {
      if let model {
        MemoryRow(memory: model)
      } else {
        ProgressView().frame(height: 120)
      }
    }
    .task { await ensureModel() }
  }
  
  private func ensureModel() async {
    do {
      let m = try MemoryModel.upsert(from: dto, in: context)
      if m.modelContext == nil { context.insert(m) }
      try context.save()
      await MainActor.run { self.model = m }
    } catch {
      print("❌ Failed to upsert global memory:", error)
    }
  }
}
