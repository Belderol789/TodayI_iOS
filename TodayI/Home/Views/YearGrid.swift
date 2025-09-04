import SwiftUI

struct YearGrid: View {
  let year: Int
  let models: [DateModel]
  @Binding var selectedMonth: Date?
  let onSelect: (Date) -> Void
  let zoomNS: Namespace.ID
  
  private let cal = Calendar.current
  private let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
  
  private var months: [Date] {
    (1...12).compactMap { cal.date(from: DateComponents(year: year, month: $0, day: 1)) }
  }
  private var grouped: [Date: [DateModel]] {
    Dictionary(grouping: models, by: { $0.date.startOfMonth(using: cal) })
  }
  
  var body: some View {
    ScrollView {
      LazyVGrid(columns: cols, spacing: 12) {
        ForEach(months, id: \.self) { month in
          // selection flag
          let isSel = selectedMonth.map {
            cal.isDate($0, equalTo: month, toGranularity: .month)
          } ?? false
          
          // normalize key and fetch models for this month
          let key = month.startOfMonth(using: cal)
          let bucket: [DateModel] = grouped[key] ?? []
          
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
              chrome: .card
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
