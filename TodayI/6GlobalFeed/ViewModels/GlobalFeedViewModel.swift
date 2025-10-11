import SwiftUI
import FirebaseFirestore

@MainActor
final class GlobalFeedViewModel: ObservableObject {
  // MARK: - Inputs / State
  @Published var day: Date
  @Published var selectedMoods: Set<Mood> = []   // multiple mood filter
  @Published var useTestData: Bool = false
  
  // Source of truth (unfiltered)
  @Published private(set) var allRows: [MemoryDTO] = []
  // Filtered rows for the list
  @Published private(set) var rows: [MemoryDTO] = []
  
  // Paging UI state
  @Published var isLoading = false
  @Published var reachedEnd = false
  @Published var errorText: String?
  
  // Global tally (from Firestore moods/{dayKey}); fallback computed from allRows
  @Published private(set) var globalMoodSlices: [MoodSlice] = []
  @Published private(set) var globalMoodTotal: Int = 0
  
  private var cursor: DocumentSnapshot?
  
  // MARK: - Init
  init(day: Date) { self.day = day }
  
  // MARK: - Public API
  
  /// Loads both the first page of the feed and the global mood tally for `day`.
  func refresh() async {
    guard !isLoading else { return }
    isLoading = true
    errorText = nil
    reachedEnd = false
    cursor = nil
    allRows = []
    rows = []
    globalMoodSlices = []
    globalMoodTotal = 0
    
    do {
      if useTestData {
        // ---- Test data path ----
        let page = GlobalFeedService.generateTestPage(for: day, count: 100, startIndex: 0)
        self.allRows = page.items
        self.cursor = nil
        self.reachedEnd = true
        
        // Build a synthetic mood tally from test data
        let counts = page.items.reduce(into: [Mood: Int]()) { dict, dto in
          if let m = Mood(rawValue: dto.mood) {
            dict[m, default: 0] += 1
          }
        }
        updateGlobalTally(from: counts)
      } else {
        // ---- Live Firestore path ----
        async let feedPage = GlobalFeedService.fetchPublicMemories(for: day, pageSize: 30, after: nil)
        async let tallyMap = MemoryService.fetchMoodTally(for: day)
        
        let page = try await feedPage
        let counts = try await tallyMap
        
        self.allRows = page.items
        self.cursor = page.lastSnapshot
        self.reachedEnd = page.items.isEmpty
        updateGlobalTally(from: counts)
      }
      
      applyFilter()
    } catch {
      errorText = error.localizedDescription
      print("⚠️ GlobalFeedViewModel.refresh failed:", error)
    }
    
    isLoading = false
  }
  
  /// Backward-compatible alias for legacy calls.
  func loadFirstPage() async { await refresh() }
  
  /// Paginates through additional feed pages.
  func loadMore() async {
    guard !isLoading, !reachedEnd, !useTestData else { return }
    isLoading = true
    errorText = nil
    
    do {
      let page = try await GlobalFeedService.fetchPublicMemories(for: day, pageSize: 30, after: cursor)
      self.allRows.append(contentsOf: page.items)
      self.cursor = page.lastSnapshot
      self.reachedEnd = page.items.isEmpty
      applyFilter()
    } catch {
      self.errorText = error.localizedDescription
      print("⚠️ loadMore failed:", error)
    }
    
    isLoading = false
  }
  
  /// Reloads everything for a new selected day.
  func setDay(_ newDay: Date) async {
    guard day != newDay else { return }
    day = newDay
    await refresh()
  }
  
  /// Fetches just the mood tally (used in GlobalFeedView .task)
  func loadGlobalMoodTally() async {
    // Test data path
    if useTestData {
      let counts = allRows.reduce(into: [Mood: Int]()) { dict, dto in
        if let m = Mood(rawValue: dto.mood) {
          dict[m, default: 0] += 1
        }
      }
      updateGlobalTally(from: counts)
      return
    }
    
    do {
      let counts = try await MemoryService.fetchMoodTally(for: day)
      updateGlobalTally(from: counts)
    } catch {
      // Fallback to locally computed
      let fallback = self.moodSlices
      self.globalMoodSlices = fallback
      self.globalMoodTotal = fallback.reduce(0) { $0 + $1.count }
      print("⚠️ fetchMoodTally failed:", error)
    }
  }
  
  // MARK: - Helpers
  
  private func updateGlobalTally(from counts: [Mood: Int]) {
    let slices = counts.map { MoodSlice(mood: $0.key, count: $0.value) }
      .sorted { $0.count > $1.count }
    globalMoodSlices = slices
    globalMoodTotal = slices.reduce(0) { $0 + $1.count }
  }
  
  // MARK: - Filtering
  
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
  
  func isMoodDisabled(_ mood: Mood) -> Bool {
    moodCounts[mood, default: 0] == 0
  }
  
  func percentage(for mood: Mood) -> Int {
    let total = totalCount
    guard total > 0 else { return 0 }
    let count = moodCounts[mood, default: 0]
    return Int((Double(count) / Double(total) * 100.0).rounded())
  }
  
  var totalCount: Int { allRows.count }
  
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
  
  private var moodCounts: [Mood: Int] {
    var dict: [Mood: Int] = [:]
    for dto in allRows {
      if let m = Mood(rawValue: dto.mood) {
        dict[m, default: 0] += 1
      }
    }
    return dict
  }
}

// MARK: - Local fallback (derived from allRows)
extension GlobalFeedViewModel {
  var moodSlices: [MoodSlice] {
    let counts = Dictionary(grouping: allRows, by: { Mood(rawValue: $0.mood) })
      .compactMapValues { $0.count }
    return counts
      .map { MoodSlice(mood: $0.key!, count: $0.value) }
      .sorted { $0.count > $1.count }
  }
  
  var totalMoodsCount: Int {
    moodSlices.reduce(0) { $0 + $1.count }
  }
}
