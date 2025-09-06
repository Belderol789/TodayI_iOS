import SwiftUI
import SwiftData

struct MonthView: View {
  let month: Date
  let models: [DateModel]
  var onSelectDate: (Date) -> Void = { _ in }
  
  // hover state lives at parent level so cells can scale above neighbors
  @State private var hoveredIndex: Int? = nil
  
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
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      TitleBar(title: monthTitle)
      
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
}

// MARK: - Subviews

private struct TitleBar: View {
  let title: String
  var onTap: (() -> Void)? = nil
  
  var body: some View {
    Button { onTap?() } label: {
      Text(title)
        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
  }
}

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
