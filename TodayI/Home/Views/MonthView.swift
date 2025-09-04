import SwiftUI
import SwiftData

// MARK: - MonthView

struct MonthView: View {
  let month: Date                       // any date in the target month
  let models: [DateModel]               // supply only models within this month
  
  // Drag-to-highlight state
  @State private var hoveredIndex: Int? = nil
  @State private var cellFrames: [Int: CGRect] = [:]
  
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
  
  private var monthTitle: String {
    let df = DateFormatter()
    df.dateFormat = "LLLL yyyy"
    return df.string(from: month)
  }
  
  // Build a grid of Date? (nil = empty box)
  private var gridDates: [Date?] {
    let cal = Calendar.current
    let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
    let daysInMonth = cal.range(of: .day, in: .month, for: start)!.count
    let firstWeekday = cal.component(.weekday, from: start) // 1=Sunday by default (locale-dependent)
    
    // Calculate leading blanks (convert to 0-based columns; align to user’s locale)
    _ = cal.shortStandaloneWeekdaySymbols // respects locale start day
    let firstWeekdayIndex = (firstWeekday - cal.firstWeekday + 7) % 7
    
    let leading = firstWeekdayIndex
    _ = leading + daysInMonth
    var result: [Date?] = Array(repeating: nil, count: leading)
    
    for day in 0..<daysInMonth {
      if let d = cal.date(byAdding: .day, value: day, to: start) {
        result.append(d)
      }
    }
    // (optional) pad trailing to complete last row to multiples of 7
    let remainder = result.count % 7
    if remainder != 0 {
      result.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
    }
    return result
  }
  
  // Map dates to models for O(1) lookup
  private var modelByDate: [Date: DateModel] {
    let cal = Calendar.current
    return Dictionary(uniqueKeysWithValues:
                        models.map { ($0.dateOnly(cal), $0) } // normalize to startOfDay
    )
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Month title
      Text(monthTitle)
        .font(.system(.title2, design: .rounded).weight(.semibold))
        .padding(.horizontal, 4)
      
      // Weekday headers (localized)
      let cal = Calendar.current
      let symbols = weekdayHeaders(using: cal)
      HStack {
        ForEach(symbols, id: \.self) { s in
          Text(s)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
      }
      
      // Grid (no outer GeometryReader)
      LazyVGrid(columns: columns, spacing: 6) {
        ForEach(gridDates.indices, id: \.self) { idx in
          let date = gridDates[idx]
          
          ZStack {
            if let date {
              if let model = modelByDate[date.startOfDay] {
                DateView(model: model)
                  .scaleEffect(hoveredIndex == idx ? 1.08 : 1.0)
                  .shadow(
                    color: (hoveredIndex == idx ? (model.moods.last?.color ?? .gray) : .clear)
                      .opacity(0.65),
                    radius: hoveredIndex == idx ? 12 : 0
                  )
              } else {
                // Empty date cell (no model)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .fill(Color.gray.opacity(0.12))
                  .overlay(
                    Text("\(Calendar.current.component(.day, from: date))")
                      .font(.system(size: 14, weight: .semibold, design: .rounded))
                      .foregroundStyle(.secondary)
                  )
                  .aspectRatio(1, contentMode: .fit)
              }
            } else {
              // Leading/trailing blank
              Color.clear
                .aspectRatio(1, contentMode: .fit)
            }
          }
          // Capture each cell's frame (in MonthView coordinate space)
          .background(
            GeometryReader { cellGeo in
              Color.clear
                .preference(
                  key: CellFrameKey.self,
                  value: [idx: cellGeo.frame(in: .named("monthArea"))]
                )
            }
          )
        }
      }
      .coordinateSpace(name: "monthArea")
      .onPreferenceChange(CellFrameKey.self) { frames in
        if frames.count != cellFrames.count { cellFrames = frames }
      }
      // Drag-to-highlight that DOESN'T steal vertical scrolling
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let dy = value.translation.height
            if abs(dy) > 6 {                // ignore real scrolling
              hoveredIndex = nil
              return
            }
            let point = value.location       // local to the grid view
            let hit = cellFrames.first { _, rect in rect.contains(point) }?.key
            if hit != hoveredIndex { hoveredIndex = hit }
          }
          .onEnded { _ in
            hoveredIndex = nil
          }
      )
    }
    .padding(8)
  }
  
  private func weekdayHeaders(using calendar: Calendar) -> [String] {
    // Rotate symbols so they start at calendar.firstWeekday
    let symbols = calendar.shortStandaloneWeekdaySymbols
    let start = calendar.firstWeekday - 1 // convert to 0-based
    return Array(symbols[start...] + symbols[..<start])
  }
}

// MARK: - PreferenceKey to collect cell frames
private struct CellFrameKey: PreferenceKey {
  static var defaultValue: [Int: CGRect] = [:]
  static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { $1 })
  }
}

fileprivate extension DateFormatter {
  static let shortDay: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "MMM d"
    return df
  }()
}

// MARK: - Preview

#Preview {
  let cal = Calendar.current
  let base = cal.date(from: DateComponents(year: 2025, month: 9, day: 1))!
  
  let models: [DateModel] = (0..<8).map { offset -> DateModel in
    let d = Calendar.current.date(byAdding: .day, value: Int(offset) * 3, to: base) ?? base
    return DateModel(date: d, moods: [.happy, .neutral, .sad] ?? [.neutral])
  }
  
  ScrollView {
    MonthView(month: base, models: models)
      .padding()
  }
}
