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
  @State private var showPremium = false
  
  var body: some View {
    NavigationStack {
      CalendarShell(year: selectedYear,
                    models: yearModels)
        .id(refreshToken) // remount when token changes (optional)
        .toolbar {
          PremiumPill(isPremium: entitlements.isPremium) {
            showPremium = true        // 👈 trigger modal
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
    .sheet(isPresented: $showPremium) {
      PremiumView()
        .presentationDetents([.large])                 // or [.fraction(0.9)]
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)             // set to true if you want to force a choice
        .presentationCornerRadius(20)                   // optional
    }
  }
  
  // MARK: - Local year load (SwiftData only)
  private func loadYear(_ year: Int) async {
    guard let swiftManager else { return }
    do {
      let rows = try swiftManager.fetchDateModels(inYear: year)
      await MainActor.run {
        // Assign only if first time or switching years
        if yearModels.isEmpty || (yearModels.first?.date.year ?? 0) != year {
          yearModels = rows
        }
      }
    } catch {
      await MainActor.run { yearModels = [] }
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
