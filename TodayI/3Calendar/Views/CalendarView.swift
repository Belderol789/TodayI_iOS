import SwiftUI
import SwiftData

struct CalendarView: View {
  
  @Environment(\.modelContext) private var context
  @Environment(\.swiftDataManager) private var swiftManager
  @EnvironmentObject private var auth: AuthStore
  @EnvironmentObject var entitlements: EntitlementStore
  @Environment(\.scenePhase) private var scenePhase
  
  @Binding var tabSelection: AppTab
  
  @State private var selectedYear = Calendar.current.component(.year, from: Date())
  @State private var yearModels: [DateModel] = []
  @State private var refreshToken = UUID()
  @State private var isSyncing = false
  @State private var errorText: String?
  @State private var showPremium = false
  
  // Face ID gating
  @AppStorage("requireFaceID") private var requireFaceID = false
  @State private var isUnlocked = false
  @State private var isAuthenticating = false
  @State private var lockError: String?
  
#if DEBUG
  @State private var useTestData = true
#endif
  
  init(tabSelection: Binding<AppTab>) {
    _tabSelection = tabSelection
  }
  
  var body: some View {
    NavigationStack {
      ZStack {
        CalendarShell(year: $selectedYear,
                      models: yearModels,
                      tabSelection: $tabSelection)
        .toolbar {
          PremiumPill(isPremium: entitlements.isPremium) {
            showPremium = true
          }
        }
        .disabled(requireFaceID && !isUnlocked)

        if requireFaceID && !isUnlocked {
          Color.black.opacity(0.65)
            .ignoresSafeArea()
            .overlay(alignment: .center) {
              VStack(spacing: 12) {
                Text("Locked")
                  .font(.headline)
                  .foregroundStyle(.white)
                
                if let lockError {
                  Text(lockError)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                } else {
                  Text("Use Face ID to view your calendar.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                }
                
                Button {
                  Task { await unlockWithFaceID() }
                } label: {
                  HStack(spacing: 8) {
                    if isAuthenticating { ProgressView() }
                    Text(isAuthenticating ? "Checking..." : "Unlock with Face ID")
                  }
                  .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(isAuthenticating)
                .padding(.horizontal, 24)
              }
            }
        }
      }
    }
    // Re-lock when backgrounded (only relevant when Face ID is enabled)
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .background, requireFaceID {
        isUnlocked = false
      } else if newPhase == .active, requireFaceID, !isUnlocked {
        Task { await unlockWithFaceID() }
      }
    }

    .task(id: "\(auth.userID ?? "nil")-\(isUnlocked)-\(requireFaceID)") {
      guard !requireFaceID || isUnlocked else { return }
      await seedDatesIfNeeded()
      await loadYear(selectedYear)
    }

    .onChange(of: selectedYear) { _, new in
      guard !requireFaceID || isUnlocked else { return }
      Task { await loadYear(new) }
    }

    .refreshable {
      guard !requireFaceID || isUnlocked else { return }
      await forceRefreshDates()
      await loadYear(selectedYear)
    }
    
    .sheet(isPresented: $showPremium) {
      PremiumView()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .presentationCornerRadius(20)
        .preferredColorScheme(.dark)
    }
    
    // Prompt Face ID on first appearance (only when enabled)
    .task {
      if requireFaceID && !isUnlocked {
        await unlockWithFaceID()
      }
    }
  }
  
  // MARK: - Face ID
  private func unlockWithFaceID() async {
    guard !isAuthenticating else { return }
    await MainActor.run {
      isAuthenticating = true
      lockError = nil
    }
    
    do {
      try await BiometricAuth.authenticate(reason: "Unlock your TodayI calendar.")
      await MainActor.run {
        isUnlocked = true
        isAuthenticating = false
        lockError = nil
      }
    } catch {
      await MainActor.run {
        isUnlocked = false
        isAuthenticating = false
        lockError = error.localizedDescription
      }
    }
  }
  
  // MARK: - Local year load (SwiftData only)
  private func loadYear(_ year: Int) async {
    guard let swiftManager else { return }
    do {
      let rows = try swiftManager.fetchDateModels(inYear: year)
      
      // ✅ resolve SwiftData faults BEFORE putting into @State
      rows.forEach { _ = $0.moodRaws }
      
      await MainActor.run {
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
      let dtos = try await MemoryService.fetchDates(for: uid) // [DateDTO]
      try swiftManager?.importDatesIfNeeded(dtos)             // upsert to SwiftData
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
