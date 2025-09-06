//
//  MonthGrid.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/7/25.
//

import SwiftUI

struct MonthGrid: View {
  let gridDates: [Date?]
  let modelByDate: [Date: DateModel]
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
      
      // Point → tile index
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
      
      let tap = SpatialTapGesture().onEnded { value in
        if let idx = indexAt(value.location),
           let date = gridDates[idx] {
          onSelectDate(date)
        }
      }
      
      let drag = DragGesture(minimumDistance: 6)
        .onChanged { value in
          let dx = value.translation.width
          let dy = value.translation.height
          if abs(dy) > abs(dx) + 6 { hoveredIndex = nil; return }
          if let idx = indexAt(value.location) { hoveredIndex = idx }
        }
        .onEnded { _ in
          defer { hoveredIndex = nil }
          if let idx = hoveredIndex,
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
                  .onTapGesture { onSelectDate(date) }
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
                  .frame(width: cellW, height: cellH)
                  .contentShape(Rectangle())
                  .scaleEffect(isToday ? 1.05 : (hoveredIndex == idx ? 1.08 : 1.0))
                  .onTapGesture { onSelectDate(date) }
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
      .background(
        GeometryReader { _ in Color.clear } // keeps builder happy
      )
      .onChange(of: geo.size) { _, newSize in gridSize = newSize } // handy if you re-add frame collection
    }
  }
}
