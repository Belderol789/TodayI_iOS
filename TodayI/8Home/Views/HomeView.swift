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
    today.formattedDayKeyLocal()
  }
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          
          // MARK: - Today
          HStack(alignment: .center) {
            SectionTitleView(title: "Today's Memory", systemImage: "sun.max.fill")
            // Override accessibility so VO doesn’t read the icon name or internal structure
              .accessibilityElement(children: .ignore)
              .accessibilityLabel("Today's Memory")
              .accessibilityAddTraits(.isHeader)
            
            Spacer()
            
            Button {
              showSetting = true
            } label: {
              Label("Profile", systemImage: "person.crop.circle")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            // Make it speak like a real action
            .accessibilityLabel(auth.isRegisteredUser ? "Profile" : "Sign in or profile")
            .accessibilityHint("Opens settings.")
            .accessibilityAddTraits(.isButton)
          }
          
          content
            .padding(.top, 4)
          // Treat the dynamic content as its own “section” for VO navigation
            .accessibilityElement(children: .contain)
          
          InsetDivider()
          // Divider is purely visual
            .accessibilityHidden(true)
          
          // MARK: - Yearly Mood Breakdown
          SectionTitleView(title: "Dominant Mood", systemImage: "face.smiling")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dominant Mood")
            .accessibilityAddTraits(.isHeader)
          
          MainMoodView(models: $yearModels)
          // If MainMoodView is visual-heavy, you can provide a summary label at the parent.
          // Adjust this later based on how MainMoodView behaves in VO.
            .accessibilityHint("Shows your most common mood for the year.")
          
          SectionTitleView(title: "Yearly Mood Breakdown", systemImage: "chart.bar")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Yearly Mood Breakdown")
            .accessibilityAddTraits(.isHeader)
          
          YearMoodBarsView(models: $yearModels)
            .accessibilityHint("Shows mood distribution by month.")
        }
        .padding(.horizontal)
      }
      .accessibilityLabel("Home")
      .navigationDestination(isPresented: $navigateToCreate) {
        CreateMemoryView()
          .accessibilityLabel("Create a Memory")
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
              .accessibilityLabel("Settings")
          } else {
            AuthView()
              .accessibilityLabel("Sign In")
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
      // Make the empty state read nicely as one message + action
      .accessibilityElement(children: .combine)
      .accessibilityLabel("No memories yet today.")
      .accessibilityHint("Create a memory to add your first entry for today.")
    } else if let randomMemory = memories.randomElement() {
      VStack(alignment: .leading, spacing: 8) {
        Text(randomMemory.date.formatted("MMM d, yyyy"))
          .font(.subheadline)
          .foregroundColor(.secondary)
          .accessibilityLabel("Date \(randomMemory.date.formatted(.dateTime.month(.abbreviated).day().year()))")
        
        MemoryRow(memory: randomMemory)
      }
      // Prefer a single coherent read: date first, then the row content
      .accessibilityElement(children: .contain)
      .accessibilityHint("Random memory from today.")
    } else {
      EmptyView()
        .accessibilityHidden(true)
    }
  }
}

// MARK: - Load memories
private extension HomeView {
  
  func loadTodayMemories() async {
    do {
      var predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey }
      if let uid = auth.userID {
        predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey && $0.userID == uid }
      }
      
      var existsFetch = FetchDescriptor<MemoryModel>(predicate: predicate)
      existsFetch.fetchLimit = 1
      let existing = try context.fetch(existsFetch)
      
      if existing.isEmpty, let uid = auth.userID {
        let dtos = try await MemoryService.fetchMemories(for: uid, dayKeyLocal: dayKey)
        try swiftManager?.importMemoriesIfNeeded(dtos)
      }
      
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
