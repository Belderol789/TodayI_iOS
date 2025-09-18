import FirebaseFirestore

@MainActor
final class GlobalFeedViewModel: ObservableObject {
  enum Mode { case live, test }
  
  @Published var day: Date
  @Published var rows: [MemoryDTO] = []
  @Published var isLoading = false
  @Published var reachedEnd = false
  @Published var errorText: String?
  @Published var mode: Mode = .live            // 👈 toggle
  
  private var cursor: DocumentSnapshot?
  
  init(day: Date) { self.day = day }
  
  func loadFirstPage() async {
    guard !isLoading else { return }
    isLoading = true; errorText = nil; reachedEnd = false; cursor = nil; rows = []
    defer { isLoading = false }
    
    switch mode {
    case .live:
      do {
        let page = try await GlobalFeedService.fetchPublicMemories(for: day, pageSize: 100, after: nil)
        self.rows = page.items
        self.cursor = page.lastSnapshot
        self.reachedEnd = page.items.isEmpty
      } catch {
        self.errorText = error.localizedDescription
      }
      
    case .test:
      // deterministic fake 100
      let page = GlobalFeedService.generateTestPage(for: day, count: 100, startIndex: 0)
      self.rows = page.items
      self.cursor = nil
      self.reachedEnd = true
    }
  }
  
  func loadMore() async {
    guard !isLoading, !reachedEnd else { return }
    isLoading = true; errorText = nil
    defer { isLoading = false }
    
    switch mode {
    case .live:
      do {
        let page = try await GlobalFeedService.fetchPublicMemories(for: day, pageSize: 100, after: cursor)
        self.rows.append(contentsOf: page.items)
        self.cursor = page.lastSnapshot
        self.reachedEnd = page.items.isEmpty
      } catch {
        self.errorText = error.localizedDescription
      }
      
    case .test:
      // all generated in first page
      reachedEnd = true
    }
  }
  
  func toggleMode() async {
    mode = (mode == .live ? .test : .live)
    await loadFirstPage()
  }
}
