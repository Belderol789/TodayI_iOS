import SwiftUI

struct MonthPager: View {
  let year: Int
  let models: [DateModel]
  @Binding var currentMonth: Date?
  let mode: CalendarMode           // or replace with `isMonthMode: Bool`
  let zoomNS: Namespace.ID
  
  private let cal = Calendar.current
  private var months: [Date] {
    (1...12).compactMap { cal.date(from: DateComponents(year: year, month: $0, day: 1)) }
  }
  private var grouped: [Date: [DateModel]] {
    Dictionary(grouping: models, by: { $0.date.startOfMonth(using: cal) })
  }
  
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        LazyVStack(spacing: 16) {
          ForEach(months, id: \.self) { month in
            let bucket = grouped[month] ?? []
            let (tint, strength) = dominantMoodTint(for: bucket)
            
            MonthContainer(
              month: month,
              id: month,
              zoomNS: zoomNS,
              isMatched: isSelected(month),
              isSource: mode == .month,
              chrome: .tinted(tint, strength: strength)   // ← mood-driven background
            ) {
              MonthView(month: month, models: bucket)      // ← remove any tint from inside MonthView
            }
            .id(month)
            .padding(.horizontal, 12)
          }
        }
        .padding(.vertical, 12)
      }
      .onAppear {
        // Scroll to initial month if it’s within this year
        if let target = currentMonth, months.contains(target) {
          proxy.scrollTo(target, anchor: .top)
        }
      }
      .onChange(of: currentMonth) { _, newVal in
        guard let target = newVal, months.contains(target) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
          proxy.scrollTo(target, anchor: .top)
        }
      }
    }
  }
  
  private func dominantMoodTint(for models: [DateModel]) -> (color: Color, strength: Double) {
    guard !models.isEmpty else { return (.clear, 0) }
    var counts: [Mood: Int] = [:]
    for m in models { for mood in m.moods { counts[mood, default: 0] += 1 } }
    
    // find max + ratio
    let total = counts.values.reduce(0, +)
    guard let (mood, maxCount) = counts.max(by: { $0.value < $1.value }) else { return (.clear, 0) }
    let ratio = Double(maxCount) / Double(max(total, 1))  // 0…1
    return (mood.color, ratio)
  }
  
  private func isSelected(_ m: Date) -> Bool {
    guard let sel = currentMonth else { return false }
    return cal.isDate(sel, equalTo: m, toGranularity: .month)
  }
}
