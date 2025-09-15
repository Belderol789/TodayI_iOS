import SwiftUI
import SwiftData

struct CalendarView: View {
  @Environment(\.modelContext) private var context
  @EnvironmentObject var entitlements: EntitlementStore
  @State private var selectedYear = Calendar.current.component(.year, from: Date())
  @State private var yearModels: [DateModel] = []
  @State private var refreshToken = UUID()          // <—
  
  var body: some View {
    NavigationStack {
      CalendarShell(year: selectedYear, models: yearModels)
        .id(refreshToken)                      // <— remount when token changes
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              YearPicker(selectedYear: $selectedYear)
            } label: {
              Label("\(selectedYear)", systemImage: "calendar")
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button(entitlements.isPremium ? "Set Free" : "Set Premium") {
              entitlements.isPremium.toggle()
            }
          }
        }
    }
    .task { await loadYear(selectedYear) }
    .onChange(of: selectedYear) { _, new in Task { await loadYear(new) } }
  }
  
  private func loadYear(_ year: Int) async {
    let cal = Calendar.current
    let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    let end   = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
    
    print("🔎 Range:", start, "→", end)
    
    let descriptor = FetchDescriptor<DateModel>(
      predicate: #Predicate { $0.date >= start && $0.date < end },
      sortBy: [SortDescriptor(\.date)]
    )
    
    do {
      let rows = try context.fetch(descriptor)
      await MainActor.run {
        self.yearModels = rows
        print("📅 Loaded \(rows.count) rows for \(year)")
      }
    } catch {
      await MainActor.run { self.yearModels = [] }
      print("Load failed:", error)
    }
  }
}
