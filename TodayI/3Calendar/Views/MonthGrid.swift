import SwiftUI

struct MonthGrid: View {
  let gridDates: [Date?]
  let modelByDate: [Date: DateModel]   // no need to make DateModel optional
  @Binding var hoveredIndex: Int?
  var onSelectDate: (Date) -> Void
  
  @State private var cellFrames: [Int: CGRect] = [:]
  @State private var gridSize: CGSize = .zero
  
  var body: some View {
    GeometryReader { geo in
      let cols = 7
      let rows = max(1, Int(ceil(Double(gridDates.count) / Double(cols))))
      let hSpace: CGFloat = 6
      let vSpace: CGFloat = 6
      let cellW = (geo.size.width  - hSpace * CGFloat(cols - 1)) / CGFloat(cols)
      let cellH = (geo.size.height - vSpace * CGFloat(rows - 1)) / CGFloat(rows)
      let items = Array(repeating: GridItem(.fixed(cellW), spacing: hSpace), count: cols)
      
      // Helpers
      let cal = Calendar.current
      let todayKey = cal.startOfDay(for: Date())
      let indexAt: (CGPoint) -> Int? = { p in
        let cw = cellW + hSpace
        let ch = cellH + vSpace
        guard cw > 0, ch > 0 else { return nil }
        let col = Int((p.x + hSpace * 0.5) / cw)
        let row = Int((p.y + vSpace * 0.5) / ch)
        guard col >= 0, col < cols, row >= 0 else { return nil }
        let idx = row * cols + col
        return idx < gridDates.count ? idx : nil
      }
      let isDisabled: (Date) -> Bool = { date in
        let key = date.today
        let isPast = key < todayKey
        let hasModel = modelByDate[key] != nil
        return isPast && !hasModel
      }
      let isSelectableAtIndex: (Int) -> Bool = { idx in
        guard let d = gridDates[idx] else { return false }
        return !isDisabled(d)
      }
      
      // Gestures (guarded by isDisabled)
      let tap = SpatialTapGesture().onEnded { value in
        if let idx = indexAt(value.location),
           let date = gridDates[idx],
           !isDisabled(date) {
          onSelectDate(date)
        }
      }
      
      let drag = DragGesture(minimumDistance: 6)
        .onChanged { value in
          let dx = value.translation.width
          let dy = value.translation.height
          if abs(dy) > abs(dx) + 6 { hoveredIndex = nil; return }
          if let idx = indexAt(value.location), isSelectableAtIndex(idx) {
            hoveredIndex = idx
          } else {
            hoveredIndex = nil
          }
        }
        .onEnded { _ in
          defer { hoveredIndex = nil }
          if let idx = hoveredIndex,
             let date = gridDates[idx],
             !isDisabled(date) {
            onSelectDate(date)
          }
        }
      
      LazyVGrid(columns: items, alignment: .center, spacing: vSpace) {
        ForEach(gridDates.indices, id: \.self) { idx in
          let dateOpt = gridDates[idx]
          
          ZStack {
            if let date = dateOpt {
              let dayNum = cal.component(.day, from: date)
              let isToday = cal.isDateInToday(date)
              let key = date.today
              let hasModel = modelByDate[key] != nil
              let disabled = isDisabled(date)
              let showsGlow = (hoveredIndex == idx || isToday) && !disabled
              
              if hasModel {
                // Date has data → full DateView (always selectable)
                DateView(model: modelByDate[key]!, showsGlow: showsGlow)
                  .frame(width: cellW, height: cellH)
                  .scaleEffect(hoveredIndex == idx ? 1.10 : (isToday ? 1.05 : 1.00))
                  .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                      .stroke(isToday ? Color.primary : .clear, lineWidth: 2)
                  )
                  .contentShape(Rectangle())
                  .allowsHitTesting(true) // selectable even in the past
              } else {
                // No model: render a “blank” day tile
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .fill(Color.gray.opacity(disabled ? 0.25 : 0.5))   // lighter if disabled
                  .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                      .stroke(isToday ? Color.primary : .clear, lineWidth: 2)
                  )
                  .overlay(
                    Text("\(dayNum)")
                      .font(.system(size: 14, weight: .semibold, design: .rounded))
                      .foregroundStyle(disabled ? .tertiary : .secondary)
                  )
                  .frame(width: cellW, height: cellH)
                  .contentShape(Rectangle())
                  .scaleEffect(disabled ? 1.00 : (isToday ? 1.05 : (hoveredIndex == idx ? 1.08 : 1.0)))
                  .opacity(disabled ? 0.6 : 1.0) // overall “disabled” feel
                  .allowsHitTesting(!disabled)   // block taps/drag on past cells without data
              }
            } else {
              Color.clear.frame(width: cellW, height: cellH)
            }
          }
          .zIndex(hoveredIndex == idx ? 1 : 0)
        }
      }
      .gesture(ExclusiveGesture(tap, drag))
      .animation(.easeOut(duration: 0.12), value: hoveredIndex)
      .background(GeometryReader { _ in Color.clear })
      .onChange(of: geo.size) { _, newSize in gridSize = newSize }
    }
  }
}
