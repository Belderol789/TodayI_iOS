import SwiftUI

struct GlobalFeedView: View {
  @StateObject private var vm: GlobalFeedViewModel
  @Binding var tabSelection: AppTab
  @EnvironmentObject private var entitlements: EntitlementStore
  
  init(tabSelection: Binding<AppTab>, day: Date = Date()) {
    _vm = StateObject(wrappedValue: GlobalFeedViewModel(day: day))
    _tabSelection = tabSelection
  }
  
  var body: some View {
    List {
      Section {
        // Use Firestore tallies if available; fall back to local
        MoodSummaryCard(
          slices: vm.globalMoodSlices.isEmpty ? vm.moodSlices : vm.globalMoodSlices,
          total: vm.globalMoodTotal > 0 ? vm.globalMoodTotal : vm.totalMoodsCount,
          tabSelection: $tabSelection
        )
        
        FeedRows(
          rows: vm.rows,
          onNearEnd: { Task { await vm.loadMore() } }
        )
        
        FooterState(
          isLoading: vm.isLoading,
          reachedEnd: vm.reachedEnd
        )
      } header: {
        GlobalFeedHeader(vm: vm)
      }
      .listSectionSeparator(.hidden, edges: .all)
    }
    .contentMargins(.horizontal, 0, for: .scrollContent)
    .listStyle(.plain)
    .navigationTitle("Global")
    .navigationBarTitleDisplayMode(.inline)
    .scrollContentBackground(.hidden)
    .toolbar { dataSourceToolbar }
    // Load feed + mood tally together
    .task { await vm.refresh() }
    .refreshable { await vm.refresh() }
  }
  
  // MARK: - Toolbar
  
  @ToolbarContentBuilder
  private var dataSourceToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Menu {
        Button("Load Firebase") {
          vm.useTestData = false
          Task { await vm.refresh() }
        }
        Button("Load Test Data") {
          vm.useTestData = true
          Task { await vm.refresh() }
        }
      } label: {
        Label("Data Source", systemImage: "ellipsis.circle")
      }
    }
    ToolbarItem(placement: .topBarTrailing) {
      Button(entitlements.isPremium ? "Set Free" : "Set Premium") {
        entitlements.isPremium.toggle()
      }
    }
  }
}

// MARK: - Subviews

private struct GlobalFeedHeader: View {
  @ObservedObject var vm: GlobalFeedViewModel
  var body: some View {
    GlassMoodFilter(vm: vm)
      .padding(.vertical, 6)
      .background(.ultraThinMaterial)
  }
}

private struct MoodSummaryCard: View {
  let slices: [MoodSlice]
  let total: Int
  @Binding var tabSelection: AppTab
  
  var body: some View {
    MoodPieChart(
      slices: slices,
      total: total,
      title: "Today the world feels",
      tabSelection: $tabSelection
    )
  }
}

private struct FeedRows: View {
  let rows: [MemoryDTO]
  let onNearEnd: () -> Void
  
  var body: some View {
    ForEach(rows, id: \.id) { dto in
      GlobalMemoryRow(dto: dto)
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .onAppear {
          if dto.id == rows.suffix(5).first?.id {
            onNearEnd()
          }
        }
    }
  }
}

private struct FooterState: View {
  let isLoading: Bool
  let reachedEnd: Bool
  
  var body: some View {
    Group {
      if isLoading {
        HStack { Spacer(); ProgressView(); Spacer() }
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
      } else if reachedEnd {
        HStack {
          Spacer()
          Text("No posts yet")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
          Spacer()
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
      }
    }
  }
}
