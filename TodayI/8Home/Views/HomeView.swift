import SwiftUI
import SwiftData

struct HomeView: View {
  
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.modelContext) private var context
  @Environment(\.swiftDataManager) private var swiftManager
  /// Needed so the Create screen pushed from here can send the user to the feed
  /// after a public post, the same as the Create tab does.
  @Binding var tabSelection: AppTab
  @State private var memories: [MemoryModel] = []
  @State private var yearModels: [DateModel] = []
  @State private var randomMemory: MemoryModel?
  @State private var isLoadingRandom = false
  @State private var streak: StreakInfo = .none
  @State private var navigateToCreate = false
  @State private var showSetting = false
  
  private var today: Date { Date().today }
  private var dayKey: String {
    today.formattedDayKeyLocal()
  }
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          
          // MARK: - Today
          HStack(alignment: .center) {
            SectionTitleView(title: "Today's Memory", systemImage: "sun.max.fill")
            // Keep the title on one line; the trailing buttons below are fixed at
            // their intrinsic width, so the title is what flexes.
              .lineLimit(1)
              .minimumScaleFactor(0.8)
            // Override accessibility so VO doesn’t read the icon name or internal structure
              .accessibilityElement(children: .ignore)
              .accessibilityLabel("Today's Memory")
              .accessibilityAddTraits(.isHeader)
            
            Spacer()

            // Always shown, zero included — hiding it at zero meant a new user
            // never discovered the mechanic. Tapping goes straight to Create while
            // today is still unwritten.
            StreakPill(streak: streak,
                       onTap: streak.loggedToday ? nil : { navigateToCreate = true })
              .fixedSize()
              .transition(.scale.combined(with: .opacity))

            Button {
              showSetting = true
            } label: {
              Label("Profile", systemImage: "person.crop.circle")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .fixedSize()
            // Make it speak like a real action
            .accessibilityLabel(auth.isRegisteredUser ? "Profile" : "Sign in or profile")
            .accessibilityHint("Opens settings.")
            .accessibilityAddTraits(.isButton)
          }
          
          if streak.days == 0 {
            Text("Keep posting daily and get a streak going.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .transition(.opacity)
              .accessibilityHidden(true)   // the pill already says this to VoiceOver
          }

          content
            .padding(.top, 4)
          // Treat the dynamic content as its own “section” for VO navigation
            .accessibilityElement(children: .contain)

          // MARK: - Random Memory
          // Hidden entirely until there's something to show, so a new install
          // doesn't stare at an empty box.
          if randomMemory != nil || isLoadingRandom {
            InsetDivider()
              .accessibilityHidden(true)

            HStack(alignment: .center) {
              SectionTitleView(title: "Random Memory", systemImage: "shuffle")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Random Memory")
                .accessibilityAddTraits(.isHeader)

              Spacer()

              Button {
                Task { await loadRandomMemory(reshuffle: true) }
              } label: {
                Label("Shuffle", systemImage: "arrow.triangle.2.circlepath")
                  .labelStyle(.iconOnly)
                  .padding(8)
                  .background(.ultraThinMaterial)
                  .clipShape(Circle())
              }
              .disabled(isLoadingRandom)
              .accessibilityLabel("Shuffle")
              .accessibilityHint("Shows a different memory from the past.")
            }

            randomContent
              .padding(.top, 4)
              .accessibilityElement(children: .contain)
          }

          InsetDivider()
          // Divider is purely visual
            .accessibilityHidden(true)

          // MARK: - Yearly Mood Breakdown
          SectionTitleView(title: "Dominant Mood", systemImage: "face.smiling")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dominant Mood")
            .accessibilityAddTraits(.isHeader)
          
          MainMoodView(models: $yearModels)
          // If MainMoodView is visual-heavy, you can provide a summary label at the parent.
          // Adjust this later based on how MainMoodView behaves in VO.
            .accessibilityHint("Shows your most common mood for the year.")
          
          SectionTitleView(title: "Yearly Mood Breakdown", systemImage: "chart.bar")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Yearly Mood Breakdown")
            .accessibilityAddTraits(.isHeader)
          
          YearMoodBarsView(models: $yearModels)
            .accessibilityHint("Shows mood distribution by month.")
        }
        .padding(.horizontal)
      }
      .accessibilityLabel("Home")
      .navigationDestination(isPresented: $navigateToCreate) {
        CreateMemoryView(tabSelection: $tabSelection)
          .accessibilityLabel("Create a Memory")
      }
      .onAppear {
        Task {
          // Local-only and instant — show it before anything touches the network,
          // then recompute once the imports below may have added days.
          refreshStreak()

          // Order matters: both imports write into SwiftData, and loadYear only reads
          // from it. Running loadYear first is why the mood charts used to stay empty
          // until you switched tabs and came back.
          await loadTodayMemories()
          await seedDatesIfNeeded()
          await loadYear(Date().year)
          await loadRandomMemory()
          // After the imports, so a fresh install counts its synced history too.
          refreshStreak()
        }
      }
      // A mood logged from a notification lands straight in SwiftData, bypassing
      // every view lifecycle hook — so refresh today's card and the streak on it.
      .onReceive(NotificationCenter.default.publisher(for: .memoryDidChangeLocally)) { _ in
        Task {
          await load(dayKey: dayKey)
          refreshStreak()
        }
      }
      .onChange(of: auth.userID) { _, _ in
        Task {
          await loadTodayMemories()
          await seedDatesIfNeeded()
          await loadYear(Date().year)
          // Different account, different history.
          await loadRandomMemory(reshuffle: true)
          refreshStreak()
        }
      }
      .sheet(isPresented: $showSetting) {
        NavigationStack {
          if auth.isRegisteredUser {
            SettingsView()
              .accessibilityLabel("Settings")
          } else {
            AuthView()
              .accessibilityLabel("Sign In")
          }
        }
      }
    }
  }
}

// MARK: - Content logic
private extension HomeView {
  @ViewBuilder
  var content: some View {
    if memories.isEmpty {
      EmptyStateView(
        message: "You don't have memories yet today",
        date: today,
        buttonTitle: "Create a Memory",
        onButtonTap: { navigateToCreate = true }
      )
      // Make the empty state read nicely as one message + action
      .accessibilityElement(children: .combine)
      .accessibilityLabel("No memories yet today.")
      .accessibilityHint("Create a memory to add your first entry for today.")
    } else if let randomMemory = memories.randomElement() {
      VStack(alignment: .leading, spacing: 8) {
        Text(randomMemory.date.formatted("MMM d, yyyy"))
          .font(.subheadline)
          .foregroundColor(.secondary)
          .accessibilityLabel("Date \(randomMemory.date.formatted(.dateTime.month(.abbreviated).day().year()))")
        
        MemoryRow(memory: randomMemory)
      }
      // Prefer a single coherent read: date first, then the row content
      .accessibilityElement(children: .contain)
      .accessibilityHint("Random memory from today.")
    } else {
      EmptyView()
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  var randomContent: some View {
    if let memory = randomMemory {
      VStack(alignment: .leading, spacing: 8) {
        Text(memory.date.formatted("MMM d, yyyy"))
          .font(.subheadline)
          .foregroundColor(.secondary)
          .accessibilityLabel("Date \(memory.date.formatted(.dateTime.month(.abbreviated).day().year()))")

        MemoryRow(memory: memory)
      }
      .accessibilityHint("A memory from an earlier day.")
    } else if isLoadingRandom {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityLabel("Looking for a past memory.")
    }
  }
}

// MARK: - Load memories
private extension HomeView {
  
  func loadTodayMemories() async {
    do {
      var predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey }
      if let uid = auth.userID {
        predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey && $0.userID == uid }
      }
      
      var existsFetch = FetchDescriptor<MemoryModel>(predicate: predicate)
      existsFetch.fetchLimit = 1
      let existing = try context.fetch(existsFetch)
      
      if existing.isEmpty, let uid = auth.userID {
        let dtos = try await MemoryService.fetchMemories(for: uid, dayKeyLocal: dayKey)
        try swiftManager?.importMemoriesIfNeeded(dtos)
      }
      
      await load(dayKey: dayKey)
    } catch {
      print("Error loading today's memories")
    }
  }
  
  /// Picks a memory from some earlier day.
  ///
  /// Local first, which is free and covers the normal case. Only when this device has
  /// never imported a past day does it hit the network, and then for a *single* day
  /// chosen from the `DateModel` list `seedDatesIfNeeded` already syncs — never the
  /// whole history. Capped at two attempts so an unlucky shuffle can't fan out.
  func loadRandomMemory(reshuffle: Bool = false) async {
    guard reshuffle || randomMemory == nil else { return }
    guard let swiftManager else { return }
    let todayKey = dayKey

    if let local = try? swiftManager.randomPastMemory(excluding: todayKey, userID: auth.userID) {
      randomMemory = local
      return
    }

    guard let uid = auth.userID,
          let candidates = try? swiftManager.pastDayKeys(before: today),
          !candidates.isEmpty
    else { return }

    isLoadingRandom = true
    for key in candidates.shuffled().prefix(2) {
      guard let dtos = try? await MemoryService.fetchMemories(for: uid, dayKeyLocal: key),
            !dtos.isEmpty
      else { continue }
      try? swiftManager.importMemoriesIfNeeded(dtos)
      if let picked = try? swiftManager.randomPastMemory(excluding: todayKey, userID: uid) {
        randomMemory = picked
        break
      }
    }
    isLoadingRandom = false
  }

  /// Local only — `DateModel` already holds every day the user journaled.
  func refreshStreak() {
    guard let swiftManager else { return }
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
      streak = swiftManager.currentStreak()
    }
  }

  /// Pulls the year's mood dots down once per launch.
  /// Home only ever *read* `DateModel`, so before this the mood charts stayed empty
  /// until the user visited the Calendar tab, which was doing the seeding.
  /// Shares `needsDateSync` with `CalendarView`, so whichever tab appears first pays
  /// for the single fetch and the other skips it.
  func seedDatesIfNeeded() async {
    guard let uid = auth.userID else { return }
    guard swiftManager?.needsDateSync == true else { return }
    do {
      let dtos = try await MemoryService.fetchDates(for: uid)
      try swiftManager?.importDatesIfNeeded(dtos)
      swiftManager?.markDatesSynced()
    } catch {
      print("⚠️ Home seedDatesIfNeeded error:", error)
    }
  }

  func loadYear(_ year: Int) async {
    guard let swiftManager else { return }
    do {
      let rows = try swiftManager.fetchDateModels(inYear: year)
      await MainActor.run { yearModels = rows }
    } catch {
      await MainActor.run { yearModels = [] }
      print("Load failed:", error)
    }
  }
  
  func load(dayKey: String) async {
    do {
      var predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey }
      
      if let uid = auth.userID {
        predicate = #Predicate<MemoryModel> { $0.userID == uid && $0.dayKey == dayKey }
      }
      
      var fetch = FetchDescriptor<MemoryModel>(predicate: predicate)
      
      if entitlements.isPremium {
        fetch.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
      } else {
        fetch.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        fetch.fetchLimit = 1
      }
      
      let items = try context.fetch(fetch)
      
      await MainActor.run {
        self.memories = items
      }
    } catch {
      print("Error loading today's memories")
    }
  }
}
