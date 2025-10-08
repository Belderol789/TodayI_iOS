import SwiftUI
import SwiftData

struct CalendarView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.swiftDataManager) private var swiftManager
  @EnvironmentObject private var auth: AuthStore
  @EnvironmentObject var entitlements: EntitlementStore
  
  @State private var selectedYear = Calendar.current.component(.year, from: Date())
  @State private var yearModels: [DateModel] = []
  @State private var refreshToken = UUID()
  @State private var isSyncing = false
  @State private var errorText: String?
  
  var body: some View {
    NavigationStack {
      CalendarShell(year: selectedYear,
                    models: yearModels)
        .id(refreshToken) // remount when token changes (optional)
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
    // Seed dates whenever user changes, then load the current year locally
    .task(id: auth.userID) {
      await seedDatesIfNeeded()
      await loadYear(selectedYear)
    }
    .onChange(of: selectedYear) { _, new in
      Task { await loadYear(new) }
    }
    .refreshable {
      await forceRefreshDates()
      await loadYear(selectedYear)
    }
  }
  
  // MARK: - Local year load (SwiftData only)
  private func loadYear(_ year: Int) async {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    let end   = cal.date(byAdding: .year, value: 1, to: start)!
    
    let descriptor = FetchDescriptor<DateModel>(
      predicate: #Predicate { $0.date >= start && $0.date < end },
      sortBy: [SortDescriptor(\.date, order: .forward)]
    )
    
    do {
      let rows = try context.fetch(descriptor)
      await MainActor.run {
        self.yearModels = rows
      }
      // print("📅 Loaded \(rows.count) DateModels for \(year)")
    } catch {
      await MainActor.run { self.yearModels = [] }
      print("Load failed:", error)
    }
  }
  
  // MARK: - Firestore seeding (lightweight) once per user
  private func seedDatesIfNeeded() async {
    guard let uid = auth.userID else { return }
    do {
      // Cheap existence check: if we already have any DateModel, we can skip
      var check = FetchDescriptor<DateModel>()
      check.fetchLimit = 1
      let existing = try context.fetch(check)
      guard existing.isEmpty else { return }
      
      isSyncing = true; errorText = nil
      let dtos = try await MemoryService.fetchDates(for: uid)         // [DateDTO]
      try swiftManager?.importDatesIfNeeded(dtos)                       // upsert to SwiftData
      isSyncing = false
    } catch {
      isSyncing = false
      errorText = error.localizedDescription
      print("⚠️ seedDatesIfNeeded error:", error)
    }
  }
  
  // MARK: - Manual sync (always hits network)
  private func forceRefreshDates() async {
    guard let uid = auth.userID else { return }
    do {
      isSyncing = true; errorText = nil
      let dtos = try await MemoryService.fetchDates(for: uid)
      try swiftManager?.importDatesIfNeeded(dtos)
      isSyncing = false
    } catch {
      isSyncing = false
      errorText = error.localizedDescription
      print("⚠️ forceRefreshDates error:", error)
    }
  }
}
