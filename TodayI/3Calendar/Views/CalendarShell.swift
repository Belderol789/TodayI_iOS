import SwiftUI

enum CalendarMode { case month, year }

struct CalendarShell: View {
  let year: Int
  let models: [DateModel]
  
  @State private var mode: CalendarMode = .month
  @State private var currentMonth: Date? = nil
  
  @Namespace private var zoomNS
  private let cal = Calendar.current
  
  // CalendarShell.swift (only the changes)
  var body: some View {
    let insets = EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16)
    
    VStack(spacing: 0) {
      header                          // already uses .padding(.horizontal, 16)
      
      ZStack {
        MonthPager(
          year: year,
          models: models,
          currentMonth: $currentMonth,
          mode: mode,
          zoomNS: zoomNS
        )
        .id(year)
        .opacity(mode == .month ? 1 : 0)
        .allowsHitTesting(mode == .month)
        .environment(\.calendarInsets, insets)   // ← inject shared inset
        
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
        .environment(\.calendarInsets, insets) // optional, if you want the grid aligned too
      }
      .animation(.spring(response: 0.5, dampingFraction: 0.85), value: mode)
    }
    .onAppear { seedCurrentMonth() }
    .onChange(of: year) { _, _ in seedCurrentMonth() }
  }
  
  // MARK: Header
  
  private var header: some View {
    HStack {
      Button {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
          mode = (mode == .month ? .year : .month)
        }
      } label: {
        HStack(spacing: 6) {
          Text(year, format: .number.grouping(.never))
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)        // ✅ adapts to light/dark (label color)
          Image(systemName: "chevron.down")
            .font(.headline)
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(mode == .year ? 180 : 0))   // flip up/down
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: mode)
        }
      }
      .buttonStyle(.plain)                      // avoids default tint styling
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
  }
  
  // MARK: Seeding
  
  /// Choose the initial/current month for a given `year`.
  /// If `year` is the current year, pick today's month; else pick January.
  private func seedCurrentMonth() {
    let today = Date()
    if cal.component(.year, from: today) == year {
      let m = cal.component(.month, from: today)
      currentMonth = cal.date(from: DateComponents(year: year, month: m, day: 1))!
    } else {
      currentMonth = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    }
  }
}
