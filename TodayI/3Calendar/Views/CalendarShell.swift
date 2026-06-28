import SwiftUI

enum CalendarMode { case month, year }

struct CalendarShell: View {
  let year: Int
  let models: [DateModel]

  @State private var mode: CalendarMode = .month
  @State private var currentMonth: Date? = nil

  @Binding var tabSelection: AppTab

  @Namespace private var zoomNS
  private let cal = Calendar.current

  // All first-of-month dates for this year
  private var months: [Date] {
    (1...12).compactMap { cal.date(from: DateComponents(year: year, month: $0, day: 1)) }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)

      if mode == .month {
        MonthPager(
          year: year,
          months: months,
          models: models,
          currentMonth: $currentMonth,
          tabSelection: $tabSelection,
          zoomNS: zoomNS
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      } else {
        YearGrid(
          year: year,
          models: models,
          selectedMonth: $currentMonth,
          onSelect: { m in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
              currentMonth = m
              mode = .month
            }
          },
          zoomNS: zoomNS
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: mode)
    .onAppear { seedCurrentMonth() }
    .onChange(of: year) { _, _ in seedCurrentMonth() }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 0) {
      // Prev month
      Button { navigateMonth(-1) } label: {
        Image(systemName: "chevron.left")
          .font(.title3.weight(.semibold))
          .frame(width: 40, height: 40)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .opacity(mode == .month ? 1 : 0)
      .disabled(mode != .month || currentMonth == months.first)

      Spacer()

      // Month + Year label — taps to toggle year grid
      Button {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
          mode = mode == .month ? .year : .month
        }
      } label: {
        HStack(spacing: 5) {
          if mode == .month, let m = currentMonth {
            Text(monthName(m))
              .font(.system(size: 22, weight: .bold, design: .rounded))
              .transition(.opacity.combined(with: .move(edge: .leading)))
          }
          Text(year, format: .number.grouping(.never))
            .font(.system(size: 22, weight: .bold, design: .rounded))
          Image(systemName: "chevron.down")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(mode == .year ? 180 : 0))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mode)
        }
        .foregroundStyle(.primary)
      }
      .buttonStyle(.plain)

      Spacer()

      // Next month
      Button { navigateMonth(1) } label: {
        Image(systemName: "chevron.right")
          .font(.title3.weight(.semibold))
          .frame(width: 40, height: 40)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .opacity(mode == .month ? 1 : 0)
      .disabled(mode != .month || currentMonth == months.last)
    }
    .animation(.easeInOut(duration: 0.2), value: mode)
    .animation(.easeInOut(duration: 0.2), value: currentMonth)
  }

  // MARK: - Helpers

  private func monthName(_ date: Date) -> String {
    let df = DateFormatter()
    df.dateFormat = "MMMM"
    return df.string(from: date)
  }

  private func navigateMonth(_ delta: Int) {
    guard let cur = currentMonth,
          let idx = months.firstIndex(where: { cal.isDate($0, equalTo: cur, toGranularity: .month) })
    else { return }
    let next = idx + delta
    guard months.indices.contains(next) else { return }
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
      currentMonth = months[next]
    }
  }

  private func seedCurrentMonth() {
    let today = Date()
    if cal.component(.year, from: today) == year {
      let m = cal.component(.month, from: today)
      currentMonth = cal.date(from: DateComponents(year: year, month: m, day: 1))
    } else {
      currentMonth = months.first
    }
  }
}
