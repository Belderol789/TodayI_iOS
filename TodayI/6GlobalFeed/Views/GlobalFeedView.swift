import SwiftUI
import SwiftData

struct GlobalFeedView: View {
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.swiftDataManager) private var swiftManager
  
  @StateObject private var vm: GlobalFeedViewModel
  @Binding var tabSelection: AppTab
  @State private var showPremium = false
  
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
        // ✅ Give the chart card a strong accessible “summary”
        .accessibilityElement(children: .contain)
        .accessibilityLabel(moodSummaryA11yTitle)
        .accessibilityHint("Shows the mood distribution for today.")
        
        FeedRows(
          rows: visibleRows,
          onNearEnd: { Task { await vm.loadMore() } },
          onBlockUser: { userID in
            swiftManager?.addBlockedUser(userID)
          }
        )
        // ✅ Group the feed rows as “Posts”
        .accessibilityElement(children: .contain)
        
        FooterState(
          isLoading: vm.isLoading,
          reachedEnd: vm.reachedEnd
        )
        // ✅ Make loading / end-of-feed understandable
        .accessibilityElement(children: .contain)
        
      } header: {
        GlobalFeedHeader(vm: vm)
        // ✅ Header semantics
          .accessibilityAddTraits(.isHeader)
          .accessibilityLabel("Filters")
          .accessibilityHint("Filter posts by mood.")
      }
      .listSectionSeparator(.hidden, edges: .all)
    }
    .contentMargins(.horizontal, 0, for: .scrollContent)
    .listStyle(.plain)
    .navigationTitle("Global")
    .navigationBarTitleDisplayMode(.inline)
    .scrollContentBackground(.hidden)
    
    // ✅ Make the screen read well when it appears
    .accessibilityLabel("Global feed")
    
    .toolbar {
      PremiumPill(isPremium: entitlements.isPremium) {
        showPremium = true
      }
      .accessibilityLabel(entitlements.isPremium ? "Premium active" : "Go Premium")
      .accessibilityHint("Opens premium options.")
    }
    
    .task { await vm.refresh() }
    .refreshable { await vm.refresh() }
    
    .sheet(isPresented: $showPremium) {
      PremiumView()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .presentationCornerRadius(20)
        .preferredColorScheme(.dark)
        .accessibilityLabel("Premium")
    }
  }
  
  // MARK: - Accessibility helpers
  private var moodSummaryA11yTitle: String {
    let total = vm.globalMoodTotal > 0 ? vm.globalMoodTotal : vm.totalMoodsCount
    return "Today the world feels. \(total) mood entries."
  }
}

// MARK: - Subviews

private struct GlobalFeedHeader: View {
  @ObservedObject var vm: GlobalFeedViewModel
  var body: some View {
    GlassMoodFilter(vm: vm)
      .padding(.vertical, 6)
      .background(.ultraThinMaterial)
    // If GlassMoodFilter is mostly UI, we avoid VO reading internal decoration twice.
      .accessibilityElement(children: .contain)
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
    // ✅ If your MoodPieChart doesn’t expose labels, at least ensure it’s discoverable
    .accessibilityElement(children: .contain)
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
      
      // ✅ Prevent List cell container from adding weird extra VO groupings
        .accessibilityElement(children: .contain)
      
        .onAppear {
          if dto.id == rows.suffix(5).first?.id {
            onNearEnd()
          }
        }
    }
    // Optional: If you want a heading for the feed region in VO rotor:
    .accessibilityLabel("Posts")
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
        // ✅ VO will announce progress properly with this label
          .accessibilityLabel("Loading more posts.")
      } else if reachedEnd {
        HStack {
          Spacer()
          Text("No more posts")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
          Spacer()
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No more posts.")
      }
    }
  }
}
