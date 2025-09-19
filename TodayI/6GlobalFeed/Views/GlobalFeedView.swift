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
        // ── Non-sticky card living under the sticky header ──
        MoodPieChart(slices: vm.moodSlices,
                     total: vm.totalMoodsCount,
                     tabSelection: $tabSelection)
        
        // ── Feed ──
        ForEach(vm.rows, id: \.id) { dto in
          GlobalMemoryRow(dto: dto)                        // your desired gutter
            .padding(.vertical, 8)
            .listRowInsets(EdgeInsets())// remove List’s insets
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .onAppear {
              if dto.id == vm.rows.suffix(5).first?.id {
                Task { await vm.loadMore() }
              }
            }
        }
        
        // ── Footer states ──
        if vm.isLoading {
          HStack { Spacer(); ProgressView(); Spacer() }
        } else if vm.reachedEnd {
          HStack { Spacer(); Text("No more posts").foregroundStyle(.secondary); Spacer() }
        }
      } header: {
        // ── Sticky header (pinned automatically) ──
        GlassMoodFilter(vm: vm)
          .padding(.vertical, 6)
          .background(.ultraThinMaterial) // glassy look
      }
    }
    .contentMargins(.horizontal, 0, for: .scrollContent)
    .listStyle(.plain)
    .navigationTitle("Global")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Load Firebase") {
            vm.useTestData = false
            Task { await vm.loadFirstPage() }
          }
          Button("Load Test Data") {
            vm.useTestData = true
            Task { await vm.loadFirstPage() }
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
    .task { await vm.loadFirstPage() }
    .refreshable { await vm.loadFirstPage() }
  }
}

// Placeholder – replace with your real view
private struct FutureView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Future View")
        .font(.headline)
      Text("This sits below the sticky filter and scrolls away with the feed.")
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemBackground))
    )
  }
}
