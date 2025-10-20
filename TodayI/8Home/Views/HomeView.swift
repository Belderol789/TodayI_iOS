import SwiftUI

struct HomeView: View {
  @Environment(\.swiftDataManager) private var swiftManager
  @State private var memories: [MemoryModel] = []
  @State private var navigateToCreate = false
  @State private var yearModels: [DateModel] = []
  
  private var today: Date { Date().today }
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          
          // MARK: - Today
          SectionTitleView(title: "Today's Memory", systemImage: "sun.max.fill")
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
        loadTodayMemories() // if sync
        Task {
          await loadYear(Date().year)
        }
      }
      .navigationTitle("Today")
    }
  }
}

// MARK: - Content logic
private extension HomeView {
  @ViewBuilder
  var content: some View {
    if memories.isEmpty {
      EmptyStateView(
        message: "You don't have any memories yet",
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
      memories = try swiftManager.loadMemories(for: Date())
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
