import SwiftUI

struct MonthPager: View {
  let year: Int
  let months: [Date]
  let models: [DateModel]
  @EnvironmentObject var entitlements: EntitlementStore
  @Binding var currentMonth: Date?
  @Binding var tabSelection: AppTab
  let zoomNS: Namespace.ID

  @Environment(\.colorScheme) private var scheme
  @State private var presentedDay: Date? = nil

  private let cal = Calendar.current
  private let insets = EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16)

  // DateModels grouped by month start
  private var grouped: [Date: [DateModel]] {
    Dictionary(grouping: models, by: { $0.date.startOfMonth(using: cal) })
  }

  var body: some View {
    TabView(selection: $currentMonth) {
      ForEach(months, id: \.self) { month in
        monthPage(month)
          .tag(month as Date?)
      }
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .sheet(isPresented: sheetIsPresentedBinding) { memorySheet }
  }

  // MARK: - Month page

  @ViewBuilder
  private func monthPage(_ month: Date) -> some View {
    let bucket = grouped[month] ?? []
    let chrome = monthChrome(for: bucket)

    MonthContainer(
      month: month,
      id: month,
      zoomNS: zoomNS,
      isMatched: isSelected(month),
      isSource: true,
      chrome: chrome,
      pageEdge: .fullBleed
    ) {
      MonthView(
        month: month,
        models: bucket,
        isPremium: $entitlements.isPremium,
        onSelectDate: { date in
          presentedDay = Calendar.current.startOfDay(for: date)
        }
      )
      .padding(.bottom, 20)
    }
    .environment(\.calendarInsets, insets)
  }

  // MARK: - Sheet

  private var sheetIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { presentedDay != nil },
      set: { if !$0 { presentedDay = nil } }
    )
  }

  @ViewBuilder
  private var memorySheet: some View {
    if let day = presentedDay {
      MemoryContainer(day: day, tabSelection: $tabSelection)
    }
  }

  // MARK: - Helpers

  private func isSelected(_ m: Date) -> Bool {
    guard let sel = currentMonth else { return false }
    return cal.isDate(sel, equalTo: m, toGranularity: .month)
  }

  private func monthChrome(for models: [DateModel]) -> MonthChrome {
    guard !models.isEmpty else { return .card }
    var counts: [Mood: Int] = [:]
    for m in models { for mood in m.moods { counts[mood, default: 0] += 1 } }
    let total = max(1, counts.values.reduce(0, +))
    let maxCount = counts.values.max() ?? 0
    let winners = Mood.allCases.filter { counts[$0] == maxCount && maxCount > 0 }
    return .tinted(winners.map(\.adaptiveColor), strength: Double(maxCount) / Double(total))
  }
}
