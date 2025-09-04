import SwiftUI

enum CalendarMode { case month, year }

struct CalendarShell: View {
  let year: Int
  let models: [DateModel]
  
  @State private var mode: CalendarMode = .month
  @State private var currentMonth: Date? = nil
  
  @Namespace private var zoomNS
  private let cal = Calendar.current
  
  var body: some View {
    VStack(spacing: 0) {
      header
      ZStack {
        MonthPager(
          year: year,
          models: models,
          currentMonth: $currentMonth,
          mode: mode,
          zoomNS: zoomNS
        )
        .opacity(mode == .month ? 1 : 0)
        .allowsHitTesting(mode == .month)
        
        YearGrid(
          year: year,
          models: models,
          selectedMonth: $currentMonth,
          onSelect: { m in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
              currentMonth = m
              mode = .month
            }
          },
          zoomNS: zoomNS
        )
        .opacity(mode == .year ? 1 : 0)
        .allowsHitTesting(mode == .year)
      }
      .animation(.spring(response: 0.5, dampingFraction: 0.85), value: mode)
    }
    .onAppear { seedCurrentMonth() }
    .onChange(of: year) { _, _ in seedCurrentMonth() }
  }
  
  private var header: some View {
    HStack {
      Button {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
          mode = (mode == .month ? .year : .month)
        }
      } label: {
        Text(year, format: .number.grouping(.never))
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .foregroundStyle(.primary)
      }
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
  }
  
  private func seedCurrentMonth() {
    let today = Date()
    let todayYear = cal.component(.year, from: today)
    if year == todayYear {
      let m = cal.date(from: DateComponents(year: year,
                                            month: cal.component(.month, from: today),
                                            day: 1))!
      currentMonth = m
    } else {
      currentMonth = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    }
  }
}
