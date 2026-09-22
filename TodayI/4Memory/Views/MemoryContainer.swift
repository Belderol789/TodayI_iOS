import SwiftUI
import SwiftData

/// Modal that displays all memories for a given calendar day.
struct MemoryContainer: View {
  
  let day: Date
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.swiftDataManager) private var swiftManager
  @Environment(\.colorScheme) private var scheme
  
  @Binding var tabSelection: AppTab
  private var today: Date { Date().today }
  
  @State private var memories: [MemoryModel] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var showPremium = false
  
  private var dayKey: String {
    day.formattedDayKeyLocal()   // make sure you have this helper
  }

  /// Free tier sees the most recent memory of the day; the rest are locked, not gone.
  private var visibleMemories: [MemoryModel] {
    guard !entitlements.isPremium else { return memories }
    return memories.suffix(1).map { $0 }
  }

  private var lockedCount: Int {
    entitlements.isPremium ? 0 : max(0, memories.count - 1)
  }
  
  // Keep the heavy formatter out of `body`
  private var titleText: String {
    day.formatted(.dateTime.weekday(.wide).month().day().year())
  }
  
  var body: some View {
    NavigationStack {
      contentView
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { }
    }
    .task {
      // Optional: show a spinner while we check/fetch
      await MainActor.run { isLoading = true; errorText = nil }
      
      do {
        
        // 1) Check if we already have at least one memory for that day (and user if available)
        var predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey }
        if let uid = auth.userID {
          predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey && $0.userID == uid }
        }
        
        var existsFetch = FetchDescriptor<MemoryModel>(predicate: predicate)
        existsFetch.fetchLimit = 1
        let existing = try context.fetch(existsFetch)
        
        // 2) If none locally, fetch from Firestore and import into SwiftData
        if existing.isEmpty, let uid = auth.userID {
          let dtos = try await MemoryService.fetchMemories(for: uid, dayKeyLocal: dayKey)
          try swiftManager?.importMemoriesIfNeeded(dtos)
        }
        
        // 3) Reload from SwiftData for display
        await load(dayKey: dayKey)
      } catch {
        await MainActor.run {
          self.errorText = error.localizedDescription
          self.isLoading = false
        }
      }
    }
    .onChange(of: entitlements.isPremium) { _, _ in
      Task { await load(dayKey: dayKey) }
    }
    .sheet(isPresented: $showPremium) {
      PremiumView()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }
  }
}

// MARK: - Locked memories
private extension MemoryContainer {
  /// Their own words, visible but out of reach — a far stronger case for Premium
  /// than a feature list, and honest about the fact that nothing was lost.
  var lockedMemoriesRow: some View {
    Button {
      showPremium = true
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "lock.fill")
          .font(.title3)
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 2) {
          Text(lockedCount == 1
               ? "1 more memory from this day"
               : "\(lockedCount) more memories from this day")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Text("Premium keeps every moment you capture.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text("Unlock")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(Capsule().fill(Color.accentColor))
      }
      .padding(14)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(.secondarySystemBackground))
      )
      .padding(.horizontal, 4)
      .padding(.vertical, 8)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(lockedCount == 1
                        ? "1 more memory from this day, locked"
                        : "\(lockedCount) more memories from this day, locked")
    .accessibilityHint("Opens Premium.")
  }
}

// MARK: - View pieces
private extension MemoryContainer {
  @ViewBuilder
  var contentView: some View {
    if isLoading {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let errorText {
      ContentUnavailableView(
        "Couldn’t load memories",
        systemImage: "exclamationmark.triangle",
        description: Text(errorText)
      )
    } else if memories.isEmpty {
      VStack {
        ContentUnavailableView(
          "No memories",
          systemImage: "book.closed",
          description: Text(day.formatted(date: .abbreviated, time: .omitted))
        )
        if day == today {
          EmptyStateView(
            message: "You don't have memories yet today",
            date: today,
            buttonTitle: "Create a Memory",
            onButtonTap: {
              dismiss()
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                tabSelection = .create
              }
            }
          )
        }
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) // ✅ key
    } else {
      List {
        ForEach(visibleMemories, id: \.id) { mem in
          MemoryRow(memory: mem, onDelete: {
            withAnimation(.easeOut(duration: 0.25)) {
              memories.removeAll { $0.id == mem.id }
            }
          })
          .padding(.vertical, 8)
          .padding(.horizontal, 4)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
        }

        if lockedCount > 0 {
          lockedMemoriesRow
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
      }
      .contentMargins(.horizontal, 0, for: .scrollContent)
      .listStyle(.plain)
      .refreshable { await load(dayKey: dayKey) }
    }
  }
  
  @ToolbarContentBuilder
  var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Button { dismiss() } label: { Image(systemName: "xmark") }
    }
    ToolbarItem(placement: .topBarTrailing) {
      Menu {
        Button("Clear memories for this day", role: .destructive) {
          Task {
            do {
              try await clearThisDay()
              await load(dayKey: dayKey)
            } catch {
              self.errorText = error.localizedDescription
            }
          }
        }
      } label: { Image(systemName: "ellipsis.circle") }
    }
  }
}

// MARK: - Data
private extension MemoryContainer {
  func load(dayKey: String) async {
    await MainActor.run {
      isLoading = true
      errorText = nil
    }
    
    do {
      var predicate = #Predicate<MemoryModel> { $0.dayKey == dayKey }
      
      if let uid = auth.userID {
        predicate = #Predicate<MemoryModel> { $0.userID == uid && $0.dayKey == dayKey }
      }
      
      // Always load the whole day. Free users used to get `fetchLimit = 1`, which
      // meant a second memory silently vanished from this screen — it was still in
      // SwiftData and Firestore, just unreachable, which reads as data loss rather
      // than a paywall. The view now shows what's locked instead of hiding it.
      var fetch = FetchDescriptor<MemoryModel>(predicate: predicate)
      fetch.sortBy = [SortDescriptor(\.createdAt, order: .forward)]

      let items = try context.fetch(fetch)
      
      await MainActor.run {
        self.memories = items
        self.isLoading = false
      }
      
    } catch {
      await MainActor.run {
        self.errorText = error.localizedDescription
        self.isLoading = false
      }
    }
  }
  
  func clearThisDay() async throws {
    // ✅ Same day-bound math as in load()
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let start = cal.startOfDay(for: day)
    let end   = cal.date(byAdding: .day, value: 1, to: start)!
    
    let fetch = FetchDescriptor<MemoryModel>(
      predicate: #Predicate { $0.date >= start && $0.date < end }
    )
    let rows = try context.fetch(fetch)
    rows.forEach { context.delete($0) }
    try context.save()
  }
}
