import SwiftUI
import SwiftData

struct HomeView: View {
  
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.modelContext) private var context
  @Environment(\.swiftDataManager) private var swiftManager
  @State private var memories: [MemoryModel] = []
  @State private var yearModels: [DateModel] = []
  @State private var navigateToCreate = false
  @State private var showSetting = false

  private var today: Date { Date().today }
  private var dayKey: String {
    today.formattedDayKeyLocal()   // make sure you have this helper
  }
  
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
          MainMoodView(models: $yearModels)
          SectionTitleView(title: "Yearly Mood Breakdown", systemImage: "chart.bar")
          YearMoodBarsView(models: $yearModels)
        }
      }
      .navigationDestination(isPresented: $navigateToCreate) {
        CreateMemoryView()
      }
      .onAppear {
        Task {
          await loadYear(Date().year)
          await loadTodayMemories()
        }
      }
      .onChange(of: auth.userID) { _, _ in
        Task {
          await loadTodayMemories()
        }
      }
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
  
  func loadTodayMemories() async {
    do {
      // 1) Check if we already have at least one memory for that day (and user if available)
      var predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey }
      if let uid = auth.userID {
        predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey && $0.userID == uid }
      }
      
      var existsFetch = FetchDescriptor<MemoryModel>(predicate: predicate)
      existsFetch.fetchLimit = 1
      let existing = try context.fetch(existsFetch)
      
      // 2) If none locally, fetch from Firestore and import into SwiftData
      if existing.isEmpty, let uid = auth.userID {
        let dtos = try await MemoryService.fetchMemories(for: uid, dayKeyLocal: dayKey)
        try swiftManager?.importMemoriesIfNeeded(dtos)
      }
      
      // 3) Reload from SwiftData for display
      await load(dayKey: dayKey)
    } catch {
      print("Error loading today's memories")
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
  
  func load(dayKey: String) async {

    do {
      var predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey }
      
      if let uid = auth.userID {
        predicate = #Predicate<MemoryModel> { $0.userID == uid && $0.dayKey == dayKey }
      }
      
      var fetch = FetchDescriptor<MemoryModel>(predicate: predicate)
      
      if entitlements.isPremium {
        fetch.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
      } else {
        fetch.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        fetch.fetchLimit = 1
      }
      
      let items = try context.fetch(fetch)
      
      await MainActor.run {
        self.memories = items
      }
      
    } catch {
      print("Error loading today's memories")
    }
  }
  
}
