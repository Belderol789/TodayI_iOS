import SwiftUI
import SwiftData
import Charts

struct MonthView: View {
  let month: Date
  let models: [DateModel]
  @Binding var isPremium: Bool
  var onSelectDate: (Date) -> Void = { _ in }
  
  // hover state lives at parent level so cells can scale above neighbors
  @State private var hoveredIndex: Int? = nil
  
  // Premium: toggle chart visibility
  @State private var showChart: Bool = false
  
  private var monthTitle: String {
    let df = DateFormatter()
    df.dateFormat = "LLLL"
    return df.string(from: month)
  }
  
  // O(1) lookup
  private var modelByDate: [Date: DateModel] {
    let cal = Calendar.current
    return Dictionary(uniqueKeysWithValues: models.map { ($0.dateOnly(cal), $0) })
  }
  
  // Grid dates (nil = blanks)
  private var gridDates: [Date?] { makeGridDates(for: month) }
  
  // ---- MoodPieChart inputs from DateModel ----
  private var moodSlices: [MoodSlice] {
    var counts: [Mood: Int] = [:]
    for m in models {
      for mood in m.moods {
        counts[mood, default: 0] += 1
      }
    }
    // Keep a stable order (optional)
    return Mood.allCases
      .map { MoodSlice(mood: $0, count: counts[$0, default: 0]) }
      .filter { $0.count > 0 }
  }
  private var totalMoodsCount: Int {
    moodSlices.reduce(0) { $0 + $1.count }
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      titleBar
      
      // Premium-only: collapsible chart
      if isPremium {
        Group {
          if showChart {
            MoodPieChart(
              slices: moodSlices,
              total: totalMoodsCount,
              selectedMoods: [],
              title: "Month feels",
              tabSelection: .constant(.calendar)
              // Keep original chart’s CTA hidden on this screen (if you use that flag)
              // showCreateButton: false
              // If your chart requires tabSelection, pass a dummy binding or refactor
              // to make the CTA optional. Assuming optional here:
            )
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity))
            .padding(.horizontal)
            .padding(.bottom, 4)
          }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showChart)
      }
      
      WeekdayHeader()
      
      MonthGrid(
        gridDates: gridDates,
        modelByDate: modelByDate,
        hoveredIndex: $hoveredIndex,
        onSelectDate: onSelectDate
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
  
  // MARK: - Title Bar
  
  private var titleBar: some View {
    Group {
      if isPremium {
        Button {
          withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            showChart.toggle()
          }
        } label: {
          HStack(spacing: 6) {
            Text(monthTitle)
              .font(.system(size: 34, weight: .bold, design: .rounded))
              .foregroundStyle(.primary)
            Image(systemName: "chevron.down")
              .font(.headline)
              .foregroundStyle(.secondary)
              .rotationEffect(.degrees(showChart ? 180 : 0))
              .animation(.spring(response: 0.45, dampingFraction: 0.8), value: showChart)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle()) // bigger tap target
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("\(monthTitle), toggle mood chart"))
      } else {
        Text(monthTitle)
          .font(.system(.largeTitle, design: .rounded).weight(.semibold))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

// MARK: - Subviews
private struct WeekdayHeader: View {
  var body: some View {
    let cal = Calendar.current
    let symbols = WeekdayHeader.weekdayHeaders(using: cal)
    
    HStack {
      ForEach(symbols, id: \.self) { s in
        Text(s)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
    }
  }
  
  static func weekdayHeaders(using calendar: Calendar) -> [String] {
    let symbols = calendar.shortStandaloneWeekdaySymbols
    let start = calendar.firstWeekday - 1
    return Array(symbols[start...] + symbols[..<start])
  }
}

// reuse helper outside the struct scope
private func weekdayHeaders(using calendar: Calendar) -> [String] {
  WeekdayHeader.weekdayHeaders(using: calendar)
}

// MARK: - Helpers

private func makeGridDates(for month: Date) -> [Date?] {
  let cal = Calendar.current
  let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
  let days = cal.range(of: .day, in: .month, for: start)!.count
  let firstWeekday = cal.component(.weekday, from: start)
  _ = cal.shortStandaloneWeekdaySymbols
  let lead = (firstWeekday - cal.firstWeekday + 7) % 7
  
  var result: [Date?] = Array(repeating: nil, count: lead)
  for d in 0..<days {
    if let day = cal.date(byAdding: .day, value: d, to: start) { result.append(day) }
  }
  let rem = result.count % 7
  if rem != 0 { result.append(contentsOf: Array(repeating: nil, count: 7 - rem)) }
  return result
}
