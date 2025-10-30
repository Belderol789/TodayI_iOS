import SwiftUI
import SwiftData

struct GlobalFeedView: View {
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.swiftDataManager) private var swiftManager
  
  @StateObject private var vm: GlobalFeedViewModel
  @Binding var tabSelection: AppTab
  @State private var showPremium = false

  // ⬇️ NEW: filter the rows you show
  // GlobalFeedView
  @Query private var blockedLists: [BlockedUserList]
  private var blockedIDs: Set<String> { Set(blockedLists.first?.users ?? []) }
  
  private var visibleRows: [MemoryDTO] {
    vm.rows.filter { !blockedIDs.contains($0.userID) }
  }
  
  init(tabSelection: Binding<AppTab>, day: Date = Date()) {
    _vm = StateObject(wrappedValue: GlobalFeedViewModel(day: day))
    _tabSelection = tabSelection
  }
  
  var body: some View {
    List {
      Section {
        MoodSummaryCard(
          slices: vm.globalMoodSlices.isEmpty ? vm.moodSlices : vm.globalMoodSlices,
          total: vm.globalMoodTotal > 0 ? vm.globalMoodTotal : vm.totalMoodsCount,
          tabSelection: $tabSelection
        )
        
        // ⬇️ pass the filtered rows + a closure to react to a block
        FeedRows(
          rows: visibleRows,
          onNearEnd: { Task { await vm.loadMore() } },
          onBlockUser: { userID in
            // 1) instant UI update
            swiftManager?.addBlockedUser(userID)
          }
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
    .toolbar {
      PremiumPill(isPremium: entitlements.isPremium) {
        showPremium = true
      }
      Button("Test Feed") {
        vm.useTestData = true
        Task { await vm.refresh() }
      }
    }
    // load feed + mood tally + blocked list
    .task {
      await vm.refresh()
    }
    .refreshable {
      await vm.refresh()
    }
    .sheet(isPresented: $showPremium) {
      PremiumView()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .presentationCornerRadius(20)
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
  let onBlockUser: (String) -> Void
  
  var body: some View {
    ForEach(rows, id: \.id) { dto in
      GlobalMemoryRow(dto: dto, onBlockUser: onBlockUser)
        .padding(8)
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
