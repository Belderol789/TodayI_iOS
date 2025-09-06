import SwiftUI
import SwiftData

struct CalendarView: View {
  @Environment(\.modelContext) private var context
  @EnvironmentObject var store: EntitlementStore
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
              
              Divider()
              
              Button("Seed \(selectedYear)") {
                do {
                  try TestManager.seedYear(selectedYear, in: context, strategy: .random)
                  print("✅ Seeding completed for year \(selectedYear)")
                  
                  // DEBUG: what’s in the store now?
                  let all = try context.fetch(FetchDescriptor<DateModel>())
                  print("📦 Total rows in store:", all.count)
                  if let first = all.first, let last = all.last {
                    print("📦 Sample:", first.date, "…", last.date)
                  }
                  
                  Task { await loadYear(selectedYear) }
                } catch {
                  print("❌ Seeding failed:", error)
                }
              }
              
              Button("Clear \(selectedYear)", role: .destructive) {
                do {
                  try TestManager.clearYear(selectedYear, in: context)
                  Task {
                    await loadYear(selectedYear)
                    await MainActor.run { refreshToken = UUID() }
                  }
                } catch {
                  print("❌ Clear failed:", error)
                }
              }
            } label: {
              Label("\(selectedYear)", systemImage: "calendar")
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button(store.isPremium ? "Set Free" : "Set Premium") {
              store.isPremium.toggle()
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

// MARK: - YearPicker (no comma formatting)
private struct YearPicker: View {
  @Binding var selectedYear: Int
  private let span = -3...3
  
  var body: some View {
    let current = Calendar.current.component(.year, from: Date())
    ForEach(span, id: \.self) { offset in
      let y = current + offset
      Button {
        selectedYear = y
      } label: {
        HStack {
          Text(y, format: .number.grouping(.never))
          if y == selectedYear { Image(systemName: "checkmark") }
        }
      }
    }
  }
}
