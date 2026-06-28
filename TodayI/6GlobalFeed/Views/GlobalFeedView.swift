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
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 12) {
          GlassMoodFilter(vm: vm)
            .padding(.top, 4)

          MoodSummaryCard(
            slices: vm.globalMoodSlices.isEmpty ? vm.moodSlices : vm.globalMoodSlices,
            total: vm.globalMoodTotal > 0 ? vm.globalMoodTotal : vm.totalMoodsCount,
            selectedMoods: vm.selectedMoods,
            tabSelection: $tabSelection
          )
          .padding(.horizontal, 16)
          .padding(.top, 8)

          if visibleRows.isEmpty && !vm.isLoading {
            emptyFeedView
          } else {
            ForEach(visibleRows, id: \.id) { dto in
              GlobalMemoryRow(dto: dto, onBlockUser: { swiftManager?.addBlockedUser($0) })
                .padding(.horizontal, 16)
                .onAppear {
                  if dto.id == visibleRows.suffix(5).first?.id {
                    Task { await vm.loadMore() }
                  }
                }
            }
          }

          footerView
        }
        .padding(.bottom, 100)
      }
      .navigationTitle("World Feed")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        PremiumPill(isPremium: entitlements.isPremium) { showPremium = true }
          .accessibilityLabel(entitlements.isPremium ? "Premium active" : "Go Premium")
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
      }
    }
  }

  // MARK: - Footer

  @ViewBuilder
  private var footerView: some View {
    if vm.isLoading {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    } else if vm.reachedEnd && !visibleRows.isEmpty {
      VStack(spacing: 8) {
        Image(systemName: "checkmark.circle")
          .font(.title2.weight(.light))
          .foregroundStyle(.secondary)
        Text("You're all caught up")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 32)
    }
  }

  // MARK: - Empty feed

  private var emptyFeedView: some View {
    VStack(spacing: 12) {
      Image(systemName: "person.2")
        .font(.system(size: 36, weight: .light))
        .foregroundStyle(.secondary)
      Text("No posts yet today")
        .font(.headline)
      Text("Be the first to share how you're feeling.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button {
        tabSelection = .create
      } label: {
        Text("Create a Memory")
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Capsule().fill(Color.accentColor))
          .foregroundColor(.white)
      }
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 48)
    .padding(.horizontal, 32)
  }
}

// MARK: - Mood summary card wrapper

private struct MoodSummaryCard: View {
  let slices: [MoodSlice]
  let total: Int
  let selectedMoods: Set<Mood>
  @Binding var tabSelection: AppTab

  var body: some View {
    MoodPieChart(
      slices: slices,
      total: total,
      selectedMoods: selectedMoods,
      title: "Today the world feels",
      tabSelection: $tabSelection
    )
    .padding(16)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(.primary.opacity(0.06), lineWidth: 1)
    )
  }
}
