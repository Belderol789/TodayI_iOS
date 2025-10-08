import SwiftUI

struct MonthPager: View {
  let year: Int
  let models: [DateModel]
  @Environment(\.colorScheme) private var scheme
  @EnvironmentObject var entitlements: EntitlementStore
  @Binding var currentMonth: Date?
  let mode: CalendarMode
  let zoomNS: Namespace.ID
  
  @State private var presentedDay: Date? = nil   // ← modal day to show
  
  private let cal = Calendar.current
  
  // First-of-month dates for this year
  private var months: [Date] {
    (1...12).compactMap { cal.date(from: DateComponents(year: year, month: $0, day: 1)) }
  }
  
  // Models grouped by month start
  private var grouped: [Date: [DateModel]] {
    Dictionary(grouping: models, by: { $0.date.startOfMonth(using: cal) })
  }
  
  // MARK: - Body
  
  var body: some View {
    scrollContent
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.viewAligned)
      .defaultScrollAnchor(.top)
      .scrollPosition(id: $currentMonth, anchor: .top)
      .animation(.spring(response: 0.5, dampingFraction: 0.9), value: currentMonth)
      .onAppear { snapCurrentToExactInstance() }
      .onChange(of: year) { _, _ in snapCurrentToExactInstance(resetIfNeeded: true) }
      .sheet(isPresented: sheetIsPresentedBinding) { memorySheet }
  }
  
  // MARK: - Subviews (composition)
  
  private var scrollContent: some View {
    ScrollView(.vertical) {
      pagesList
        .scrollTargetLayout()
        .contentMargins(.vertical, 0, for: .scrollContent)
    }
  }
  
  private var pagesList: some View {
    LazyVStack(spacing: 0) {
      ForEach(months, id: \.self) { month in
        monthPage(month)
      }
    }
  }
  
  @ViewBuilder
  private func monthPage(_ month: Date) -> some View {
    let bucket = grouped[month] ?? []
    let chrome = monthChrome(for: bucket, scheme: scheme)
    
    MonthContainer(
      month: month,
      id: month,
      zoomNS: zoomNS,
      isMatched: isSelected(month),
      isSource: mode == .month,
      chrome: chrome,
      pageEdge: .fullBleed
    ) {
      MonthView(
        month: month,
        models: bucket,
        isPremium: $entitlements.isPremium,
        onSelectDate: { date in
          // ✅ Show MemoryContainer for the tapped day
          presentedDay = Calendar.current.startOfDay(for: date)
        }
      )
      .frame(maxHeight: .infinity, alignment: .top)
    }
    .id(month)
    .containerRelativeFrame(.vertical)   // each page = viewport height
  }
  
  // MARK: - Sheet pieces
  
  private var sheetIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { presentedDay != nil },
      set: { if !$0 { presentedDay = nil } }
    )
  }
  
  @ViewBuilder
  private var memorySheet: some View {
    if let day = presentedDay {
      // EntitlementStore is expected via .environmentObject higher up
      MemoryContainer(day: day)
    }
  }
  
  // MARK: - Helpers
  
  private func isSelected(_ m: Date) -> Bool {
    guard let sel = currentMonth else { return false }
    return cal.isDate(sel, equalTo: m, toGranularity: .month)
  }
  
  private func monthChrome(for models: [DateModel], scheme: ColorScheme) -> MonthChrome {
    guard !models.isEmpty else { return .card }
    var counts: [Mood: Int] = [:]
    for m in models { for mood in m.moods { counts[mood, default: 0] += 1 } }
    let total = max(1, counts.values.reduce(0, +))
    let maxCount = counts.values.max() ?? 0
    let winners = Mood.allCases.filter { counts[$0] == maxCount && maxCount > 0 }
    let colors = winners.map { $0.adaptiveColor }
    let strength = Double(maxCount) / Double(total)
    return .tinted(colors, strength: strength)
  }
  
  /// Ensure `currentMonth` equals the *exact* Date object from `months`.
  private func snapCurrentToExactInstance(resetIfNeeded: Bool = false) {
    let wanted: Date = {
      if let cm = currentMonth, cal.component(.year, from: cm) == year { return cm }
      let today = Date()
      if cal.component(.year, from: today) == year {
        let m = cal.component(.month, from: today)
        return cal.date(from: DateComponents(year: year, month: m, day: 1))!
      }
      return cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    }()
    
    if let exact = months.first(where: { cal.isDate($0, equalTo: wanted, toGranularity: .month) }) {
      var txn = Transaction(); txn.disablesAnimations = true
      withTransaction(txn) {
        if resetIfNeeded || currentMonth == nil ||
            !cal.isDate(exact, equalTo: currentMonth!, toGranularity: .month) {
          currentMonth = exact
        }
      }
    } else {
      currentMonth = wanted
    }
  }
}
