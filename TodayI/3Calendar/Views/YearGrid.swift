import SwiftUI

struct YearGrid: View {
  let year: Int
  let models: [DateModel]
  @Environment(\.colorScheme) private var scheme
  @Binding var selectedMonth: Date?
  
  let onSelect: (Date) -> Void
  let zoomNS: Namespace.ID
  
  private let cal = Calendar.current
  private let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
  
  // Months for the given year
  private var months: [Date] {
    (1...12).compactMap { cal.date(from: DateComponents(year: year, month: $0, day: 1)) }
  }
  
  // Group DateModels by month
  private var grouped: [Date: [DateModel]] {
    Dictionary(grouping: models, by: { $0.date.startOfMonth(using: cal) })
  }
  
  // Aggregate mood counts across the whole year
  private var moodSlices: [MoodSlice] {
    var counts: [Mood: Int] = [:]
    for m in models {
      for mood in m.moods {
        counts[mood, default: 0] += 1
      }
    }
    return counts.map { MoodSlice(mood: $0.key, count: $0.value) }
  }
  
  private var totalMoodsCount: Int {
    moodSlices.reduce(0) { $0 + $1.count }
  }
  
  // MARK: - Body
  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        // ── 🔹 Mood Pie Chart on top ──
        MoodPieChart(
          slices: moodSlices,
          total: totalMoodsCount,
          selectedMoods: [],
          title: "Year feels",
          tabSelection: .constant(.calendar)
        )
        .padding(.horizontal)
        .padding(.top, 8)
        
        // ── 🔹 Year grid ──
        LazyVGrid(columns: cols, spacing: 12) {
          ForEach(months, id: \.self) { month in
            let isSel = selectedMonth.map {
              cal.isDate($0, equalTo: month, toGranularity: .month)
            } ?? false
            
            let bucket = grouped[month] ?? []
            let chrome = monthChrome(for: bucket, scheme: scheme)
            
            Button {
              selectedMonth = month
              onSelect(month)
            } label: {
              MonthContainer(
                month: month,
                id: month,
                zoomNS: zoomNS,
                isMatched: isSel,
                isSource: false,
                chrome: chrome,
                pageEdge: .rounded
              ) {
                MonthThumbnail(month: month, models: bucket)
              }
              .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .stroke(isSel ? Color.accentColor.opacity(0.35) : .clear, lineWidth: 2)
              )
              .contentTransition(.interpolate)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(16)
      }
    }
  }
  
  // MARK: - Helpers
  
  private func monthChrome(for models: [DateModel], scheme: ColorScheme) -> MonthChrome {
    guard !models.isEmpty else { return .card }
    
    var counts: [Mood: Int] = [:]
    for m in models {
      for mood in m.moods {
        counts[mood, default: 0] += 1
      }
    }
    
    let total = max(1, counts.values.reduce(0, +))
    let maxCount = counts.values.max() ?? 0
    
    let winners = Mood.allCases.filter { counts[$0] == maxCount && maxCount > 0 }
    let colors = winners.map { $0.adaptiveColor }
    let strength = Double(maxCount) / Double(total)
    
    return .tinted(colors, strength: strength)
  }
}
