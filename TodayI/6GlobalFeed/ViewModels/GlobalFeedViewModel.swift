import SwiftUI
import FirebaseFirestore

@MainActor
final class GlobalFeedViewModel: ObservableObject {
  // MARK: - Inputs / State
  @Published var day: Date
  @Published var selectedMoods: Set<Mood> = []   // ← multiple moods
  @Published var useTestData: Bool = false
  
  // Unfiltered source of truth
  @Published private(set) var allRows: [MemoryDTO] = []
  // Filtered rows for the List
  @Published private(set) var rows: [MemoryDTO] = []
  
  // Paging UI state
  @Published var isLoading = false
  @Published var reachedEnd = false
  @Published var errorText: String?
  
  private var cursor: DocumentSnapshot?
  
  init(day: Date) { self.day = day }
  
  // MARK: - Loading
  func loadFirstPage() async {
    guard !isLoading else { return }
    isLoading = true; errorText = nil; reachedEnd = false; cursor = nil
    allRows = []; rows = []
    
    do {
      if useTestData {
        let page = GlobalFeedService.generateTestPage(for: day, count: 100, startIndex: 0)
        self.allRows = page.items
        self.cursor = nil
        self.reachedEnd = true
      } else {
        let page = try await GlobalFeedService.fetchPublicMemories(for: day, pageSize: 30, after: nil)
        self.allRows = page.items
        self.cursor = page.lastSnapshot
        self.reachedEnd = page.items.isEmpty
      }
      applyFilter()
    } catch {
      self.errorText = error.localizedDescription
    }
    isLoading = false
  }
  
  func loadMore() async {
    guard !isLoading, !reachedEnd else { return }
    isLoading = true; errorText = nil
    
    do {
      if useTestData {
        let start = allRows.count
        let page = GlobalFeedService.generateTestPage(for: day, count: 30, startIndex: start)
        self.allRows.append(contentsOf: page.items)
        self.reachedEnd = allRows.count >= 100
      } else {
        let page = try await GlobalFeedService.fetchPublicMemories(for: day, pageSize: 30, after: cursor)
        self.allRows.append(contentsOf: page.items)
        self.cursor = page.lastSnapshot
        self.reachedEnd = page.items.isEmpty
      }
      applyFilter()
    } catch {
      self.errorText = error.localizedDescription
    }
    isLoading = false
  }
  
  // MARK: - Filter controls (for GlassMoodFilter)
  func toggleMood(_ mood: Mood) {
    if selectedMoods.contains(mood) {
      selectedMoods.remove(mood)
    } else {
      selectedMoods.insert(mood)
    }
    applyFilter()
  }
  
  func clearMoodFilter() {
    selectedMoods.removeAll()
    applyFilter()
  }
  
  // Disable a segment if there are 0 items for that mood
  func isMoodDisabled(_ mood: Mood) -> Bool {
    moodCounts[mood, default: 0] == 0
  }
  
  // Percentage label for a mood out of the currently loaded (unfiltered) set
  func percentage(for mood: Mood) -> Int {
    let total = totalCount
    guard total > 0 else { return 0 }
    let count = moodCounts[mood, default: 0]
    return Int((Double(count) / Double(total) * 100.0).rounded())
  }
  
  var totalCount: Int { allRows.count }
  
  // MARK: - Internals
  private func applyFilter() {
    if selectedMoods.isEmpty {
      rows = allRows
    } else {
      rows = allRows.filter { dto in
        guard let m = Mood(rawValue: dto.mood) else { return false }
        return selectedMoods.contains(m)
      }
    }
  }
  
  // Distribution computed from the unfiltered list
  private var moodCounts: [Mood: Int] {
    var dict: [Mood: Int] = [:]
    for m in Mood.allCases { dict[m] = 0 }
    for dto in allRows {
      if let m = Mood(rawValue: dto.mood) {
        dict[m, default: 0] += 1
      }
    }
    return dict
  }
}
