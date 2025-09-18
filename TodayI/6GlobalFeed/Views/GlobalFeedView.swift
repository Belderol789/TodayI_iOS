import SwiftUI

struct GlobalFeedView: View {
  @StateObject private var vm: GlobalFeedViewModel
  
  init(day: Date = Date()) {
    _vm = StateObject(wrappedValue: GlobalFeedViewModel(day: day))
  }
  
  var body: some View {
    List {
      ForEach(vm.rows, id: \.id) { dto in
        GlobalMemoryRow(dto: dto)
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
          .onAppear {
            if dto.id == vm.rows.suffix(5).first?.id {
              Task { await vm.loadMore() }
            }
          }
      }
      
      if vm.isLoading {
        HStack { Spacer(); ProgressView(); Spacer() }
      } else if vm.reachedEnd {
        HStack { Spacer(); Text("No more posts").foregroundStyle(.secondary); Spacer() }
      }
    }
    .listStyle(.plain)
    .navigationTitle(vm.mode == .live ? "Global (Live)" : "Global (Test)")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(vm.mode == .live ? "Use Test" : "Use Live") {
          Task { await vm.toggleMode() }
        }
      }
    }
    .task { await vm.loadFirstPage() }
    .refreshable { await vm.loadFirstPage() }
  }
}
