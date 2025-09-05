import SwiftUI
import SwiftData

// MARK: - MonthView

struct MonthView: View {
  let month: Date                       // any date in the target month
  let models: [DateModel]               // supply only models within this month
  
  // Hover state
  @State private var hoveredIndex: Int? = nil
  @State private var cellFrames: [Int: CGRect] = [:]
  @State private var gridSize: CGSize = .zero   // ← track grid size to invalidate frames on resize
  
  private var monthTitle: String {
    let df = DateFormatter()
    df.dateFormat = "LLLL"
    return df.string(from: month)
  }
  
  // Build a grid of Date? (nil = empty box)
  private var gridDates: [Date?] {
    let cal = Calendar.current
    let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
    let daysInMonth = cal.range(of: .day, in: .month, for: start)!.count
    let firstWeekday = cal.component(.weekday, from: start)
    
    _ = cal.shortStandaloneWeekdaySymbols // respect locale
    let firstWeekdayIndex = (firstWeekday - cal.firstWeekday + 7) % 7
    
    var result: [Date?] = Array(repeating: nil, count: firstWeekdayIndex)
    for day in 0..<daysInMonth {
      if let d = cal.date(byAdding: .day, value: day, to: start) { result.append(d) }
    }
    let remainder = result.count % 7
    if remainder != 0 { result.append(contentsOf: Array(repeating: nil, count: 7 - remainder)) }
    return result
  }
  
  // Map dates to models for O(1) lookup
  private var modelByDate: [Date: DateModel] {
    let cal = Calendar.current
    return Dictionary(uniqueKeysWithValues: models.map { ($0.dateOnly(cal), $0) })
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // 1) Title (aligned by MonthContainer's leading inset)
      Text(monthTitle)
        .font(.system(.title, design: .rounded).weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
      
      // 2) Weekday headers
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
      
      // 3) Grid fills remaining space
      GeometryReader { geo in
        let cols = 7
        let rows = max(1, Int(ceil(Double(gridDates.count) / Double(cols))))
        let hSpace: CGFloat = 6
        let vSpace: CGFloat = 6
        
        // Compute rectangular cells to fill the page
        let cellW = (geo.size.width  - hSpace * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH = (geo.size.height - vSpace * CGFloat(rows - 1)) / CGFloat(rows)
        
        let items = Array(repeating: GridItem(.fixed(cellW), spacing: hSpace), count: cols)
        
        LazyVGrid(columns: items, alignment: .center, spacing: vSpace) {
          ForEach(gridDates.indices, id: \.self) { idx in
            let date = gridDates[idx]
            
            ZStack {
              if let date {
                let isToday = Calendar.current.isDateInToday(date)
                let borderColor = Color.primary   // black in light, white in dark
                
                if let model = modelByDate[date.startOfDay] {
                  
                  DateView(model: model, showsGlow: (hoveredIndex == idx) || isToday)
                    .frame(width: cellW, height: cellH)
                    .scaleEffect(
                      hoveredIndex == idx ? 1.10 :
                        (isToday ? 1.05 : 1.00)
                    )
                    .contentShape(Rectangle())
                    .overlay(
                      RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isToday ? borderColor : .clear, lineWidth: 2)
                    )
                    .shadow(
                      color: isToday ? borderColor.opacity(0.2) : .clear,
                      radius: isToday ? 2 : 0
                    )
                } else {
                  // Empty date (no model) — rectangular cell with optional "today" styling
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.5))
                    .overlay(
                      RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isToday ? borderColor : .clear, lineWidth: 2)
                    )
                    .overlay(
                      Text(Calendar.current.component(.day, from: date).description)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    )
                    .shadow(
                      color: isToday ? borderColor.opacity(0.2) : .clear,
                      radius: isToday ? 2 : 0
                    )
                    .frame(width: cellW, height: cellH)
                    .contentShape(Rectangle())
                    .scaleEffect(isToday ? 1.05 : (hoveredIndex == idx ? 1.08 : 1.0))
                }
              } else {
                Color.clear.frame(width: cellW, height: cellH)
              }
            }
            .zIndex(hoveredIndex == idx ? 1 : 0)
            .background(
              GeometryReader { cellGeo in
                Color.clear.preference(
                  key: CellFrameKey.self,
                  value: [idx: cellGeo.frame(in: .named("monthGrid"))]
                )
              }
            )
            // Smooth pop for hover/today changes
            .animation(.easeOut(duration: 0.12), value: hoveredIndex)
          }
        }
        .coordinateSpace(name: "monthGrid")
        // Recompute frames only when count changes OR the grid resizes
        .onPreferenceChange(CellFrameKey.self) { frames in
          if frames.count != cellFrames.count || gridSize != geo.size {
            cellFrames = frames
          }
        }
        .onChange(of: geo.size) { _, newSize in
          if newSize != gridSize {
            gridSize = newSize
            // Invalidate frames; they'll be recollected on next pass
            cellFrames = [:]
          }
        }
        // Horizontal-first hover gesture (doesn't block vertical paging)
        .simultaneousGesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              let dx = value.translation.width
              let dy = value.translation.height
              if abs(dy) > abs(dx) + 8 { // clearly vertical → let paging win
                hoveredIndex = nil
                return
              }
              let p = value.location
              if let hit = cellFrames.first(where: { $0.value.contains(p) })?.key,
                 hit != hoveredIndex {
                hoveredIndex = hit
              }
            }
            .onEnded { _ in hoveredIndex = nil }
        )
        .animation(.easeOut(duration: 0.12), value: hoveredIndex)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
  
  private func weekdayHeaders(using calendar: Calendar) -> [String] {
    let symbols = calendar.shortStandaloneWeekdaySymbols
    let start = calendar.firstWeekday - 1
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
