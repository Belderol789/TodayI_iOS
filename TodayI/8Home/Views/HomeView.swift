import SwiftUI

struct HomeView: View {
  
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.swiftDataManager) private var swiftManager
  @State private var memories: [MemoryModel] = []
  @State private var yearModels: [DateModel] = []
  @State private var navigateToCreate = false
  @State private var showSetting = false
  
  private var today: Date { Date().today }
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          
          // MARK: - Today
          HStack {
            SectionTitleView(title: "Today's Memory", systemImage: "sun.max.fill")
            Button {
              showSetting = true
              // Action here
            } label: {
              Label("Profile", systemImage: "person.crop.circle")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
          }
          content
            .padding(.top, 4)
          
          InsetDivider()
          
          // MARK: - Yearly Mood Breakdown
          SectionTitleView(title: "Dominant Mood", systemImage: "face.smiling")
          MainMoodView(models: yearModels)
          SectionTitleView(title: "Yearly Mood Breakdown", systemImage: "chart.bar")
          YearMoodBarsView(models: yearModels)
        }
      }
      .navigationDestination(isPresented: $navigateToCreate) {
        CreateMemoryView()
      }
      .onAppear {
        Task {
          await loadYear(Date().year)
          loadTodayMemories()
        }
      }
      .onChange(of: auth.userID, { oldValue, newValue in
        loadTodayMemories() // if sync
      })
      .sheet(isPresented: $showSetting) {
        NavigationStack {
          if auth.isRegisteredUser {
            SettingsView()
          } else {
            AuthView()
          }
        }
      }
    }
  }
}

// MARK: - Content logic
private extension HomeView {
  @ViewBuilder
  var content: some View {
    if memories.isEmpty {
      EmptyStateView(
        message: "You don't have memories yet today",
        date: today,
        buttonTitle: "Create a Memory",
        onButtonTap: { navigateToCreate = true }
      )
    } else if let randomMemory = memories.randomElement() {
      VStack {
        Text(randomMemory.date.formatted("MMM d, yyyy"))
          .font(.subheadline)
          .foregroundColor(.secondary)
        MemoryRow(memory: randomMemory)
      }
    } else {
      EmptyView()
    }
  }
}

// MARK: - Load memories
private extension HomeView {
  
  func loadTodayMemories() {
    guard let swiftManager else { return }
    do {
      memories = try swiftManager.loadMemories(for: Date(), userID: auth.userID ?? nil)
    } catch {
      print("❌ Failed to load memories: \(error.localizedDescription)")
      memories = []
    }
  }
  
  func loadYear(_ year: Int) async {
    guard let swiftManager else { return }
    do {
      let rows = try swiftManager.fetchDateModels(inYear: year)
      await MainActor.run { yearModels = rows }
    } catch {
      await MainActor.run { yearModels = [] }
      print("Load failed:", error)
    }
  }
  
}
