import SwiftUI
import SwiftData

struct MonthView: View {
  let month: Date
  let models: [DateModel]
  var onSelectDate: (Date) -> Void = { _ in }   // central callback
  
  @State private var hoveredIndex: Int? = nil
  @State private var cellFrames: [Int: CGRect] = [:]
  @State private var gridSize: CGSize = .zero
  
  
  private var monthTitle: String {
    let df = DateFormatter()
    df.dateFormat = "LLLL"
    return df.string(from: month)
  }
  
  private var modelByDate: [Date: DateModel] {
    let cal = Calendar.current
    return Dictionary(uniqueKeysWithValues: models.map { ($0.dateOnly(cal), $0) })
  }
  
  private var gridDates: [Date?] {
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
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Title
      Button {} label: {
        Text(monthTitle)
          .font(.system(.largeTitle, design: .rounded).weight(.semibold))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      
      // Weekday headers
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
      
      // Grid
      GeometryReader { geo in
        let cols = 7
        let rows = max(1, Int(ceil(Double(gridDates.count) / Double(cols))))
        let hSpace: CGFloat = 6
        let vSpace: CGFloat = 6
        let cellW = (geo.size.width  - hSpace * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH = (geo.size.height - vSpace * CGFloat(rows - 1)) / CGFloat(rows)
        let items = Array(repeating: GridItem(.fixed(cellW), spacing: hSpace), count: cols)
        
        // Define gestures
        let tap = SpatialTapGesture().onEnded { value in
          // location is in monthGrid space
          if let hit = cellFrames.first(where: { $0.value.contains(value.location) })?.key,
             let date = gridDates[hit] {
            onSelectDate(date)
          }
        }
        
        let drag = DragGesture(minimumDistance: 6)
          .onChanged { value in
            let dx = value.translation.width
            let dy = value.translation.height
            if abs(dy) > abs(dx) + 6 { hoveredIndex = nil; return }
            let p = value.location
            if let hit = cellFrames.first(where: { $0.value.contains(p) })?.key {
              hoveredIndex = hit
            }
          }
          .onEnded { _ in
            defer { hoveredIndex = nil }
            if let idx = hoveredIndex,
               idx < gridDates.count,
               let date = gridDates[idx] {
              onSelectDate(date)
            }
          }
        
        LazyVGrid(columns: items, alignment: .center, spacing: vSpace) {
          ForEach(gridDates.indices, id: \.self) { idx in
            let dateOpt = gridDates[idx]
            
            ZStack {
              if let date = dateOpt {
                let isToday = Calendar.current.isDateInToday(date)
                let borderColor = Color.primary
                
                if let model = modelByDate[date.startOfDay] {
                  DateView(model: model, showsGlow: (hoveredIndex == idx) || isToday)
                    .frame(width: cellW, height: cellH)
                    .scaleEffect(hoveredIndex == idx ? 1.10 : (isToday ? 1.05 : 1.00))
                    .contentShape(Rectangle())
                    .overlay(
                      RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isToday ? borderColor : .clear, lineWidth: 2)
                    )
                    .onTapGesture { onSelectDate(date) }   // ✅ unwrap before calling
                } else {
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.5))
                    .overlay(
                      RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isToday ? borderColor : .clear, lineWidth: 2)
                    )
                    .overlay(
                      Text(Calendar.current.component(.day, from: date).description)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    )
                    .shadow(color: isToday ? borderColor.opacity(0.2) : .clear, radius: isToday ? 2 : 0)
                    .frame(width: cellW, height: cellH)
                    .contentShape(Rectangle())
                    .scaleEffect(isToday ? 1.05 : (hoveredIndex == idx ? 1.08 : 1.0))
                    .onTapGesture { onSelectDate(date) }   // ✅ unwrap before calling
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
          }
        }
        .coordinateSpace(name: "monthGrid")
        .onPreferenceChange(CellFrameKey.self) { frames in
          if frames.count != cellFrames.count || gridSize != geo.size {
            cellFrames = frames
          }
        }
        .onChange(of: geo.size) { _, newSize in
          if newSize != gridSize {
            gridSize = newSize
            cellFrames = [:]
          }
        }
        .gesture(ExclusiveGesture(tap, drag))
        .animation(.easeOut(duration: 0.12), value: hoveredIndex)   // ✅ single animation place
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

// PreferenceKey unchanged
private struct CellFrameKey: PreferenceKey {
  static var defaultValue: [Int: CGRect] = [:]
  static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { $1 })
  }
}
