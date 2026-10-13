//
//  CloudBackupBadge.swift
//  TodayI
//
//  Whether one of your entries is in TodayI's cloud, and the switch to change it.
//

import SwiftUI

/// The cloud beside the Personal/Global badge on your own entries.
///
/// Backup is what Premium is sold on, and it used to be invisible: nobody could tell
/// which entries were actually safe. Blue means the entry is in Firestore, gray means it
/// lives on this iPhone only, and a cloud with an arrow means it's waiting to upload
/// (offline, or a failed upload the next drain retries) — showing that as blue would
/// claim a backup that doesn't exist yet.
///
/// Styled like Create's compact privacy badge: a tinted glyph whose word appears briefly
/// after a change. The first tap ever explains the colours and offers the change; after
/// that a tap just does it.
struct CloudBackupBadge: View {
  let memory: MemoryModel
  @EnvironmentObject private var entitlements: EntitlementStore

  @AppStorage("cloudBadgeExplained") private var explained = false
  @State private var showExplainer = false
  @State private var showGlobalInfo = false
  @State private var showPremium = false
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var showTransientLabel = false
  @State private var labelTask: Task<Void, Never>?

  enum Status { case global, backedUp, pending, localOnly }

  private var status: Status {
    if memory.isPublic { return .global }
    if memory.keepLocalOnly { return .localOnly }
    if !memory.needsCloudBackup { return .backedUp }
    // Not uploaded yet: on Premium it's queued; on the free tier it stays on the device.
    return entitlements.isPremium ? .pending : .localOnly
  }

  private var icon: String {
    switch status {
    case .global, .backedUp: return "icloud.fill"
    case .pending:           return "icloud.and.arrow.up"
    case .localOnly:         return "icloud"
    }
  }

  private var tint: Color {
    status == .localOnly ? Color.secondary : Color.blue
  }

  private var label: String {
    switch status {
    case .global, .backedUp: return "Backed up"
    case .pending:           return "Uploading"
    case .localOnly:         return "This iPhone only"
    }
  }

  var body: some View {
    Button(action: tapped) {
      HStack(spacing: 6) {
        if isWorking {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: icon)
            .font(.subheadline.weight(.semibold))
        }
        if showTransientLabel {
          Text(label)
            .font(.subheadline.weight(.semibold))
            .fixedSize()
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
      }
      .foregroundStyle(tint)
      .padding(2)
    }
    .buttonStyle(.plain)
    .disabled(isWorking)
    .onDisappear { labelTask?.cancel() }
    .accessibilityLabel("Cloud backup")
    .accessibilityValue(label)
    .alert(explainerTitle, isPresented: $showExplainer) {
      explainerActions
    } message: {
      Text(explainerMessage)
    }
    .alert("Global posts live in the cloud", isPresented: $showGlobalInfo) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("That's how they reach the World feed. Make this entry Personal first if you'd like to keep it on this iPhone only.")
    }
    .alert("Couldn't change backup", isPresented: Binding(
      get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
    .sheet(isPresented: $showPremium) {
      PremiumView()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
  }

  // MARK: - Taps

  private func tapped() {
    if status == .global { showGlobalInfo = true; return }
    // Once, ever: what the colours mean, with the change as the alert's action. After
    // that, no confirmations — the transient label says what just happened.
    guard explained else { showExplainer = true; return }
    perform()
  }

  private func perform() {
    switch status {
    case .global:
      showGlobalInfo = true
    case .backedUp, .pending:
      Task { await keepOnDevice() }
    case .localOnly:
      if entitlements.isPremium {
        Task { await backUp() }
      } else {
        showPremium = true
      }
    }
  }

  // MARK: - Explainer

  private var explainerTitle: String { "Cloud backup" }

  private var explainerMessage: String {
    let colours = "A blue cloud means this entry is backed up to TodayI's cloud, so it's safe if you lose or replace your iPhone. A gray cloud means it's kept on this iPhone only (and in your iPhone's own iCloud backup). Either way, the day's mood still syncs to your calendar."
    switch status {
    case .localOnly where !entitlements.isPremium:
      return colours + "\n\nBacking up your journal is part of Premium."
    case .backedUp, .pending:
      return colours + "\n\nKeeping this one on your iPhone removes its cloud copy."
    default:
      return colours
    }
  }

  @ViewBuilder
  private var explainerActions: some View {
    switch status {
    case .backedUp, .pending:
      Button("Keep on This iPhone Only", role: .destructive) { explained = true; perform() }
      Button("Cancel", role: .cancel) { explained = true }
    case .localOnly where entitlements.isPremium:
      Button("Back Up to Cloud") { explained = true; perform() }
      Button("Cancel", role: .cancel) { explained = true }
    case .localOnly:
      Button("See Premium") { explained = true; perform() }
      Button("Not Now", role: .cancel) { explained = true }
    case .global:
      Button("OK", role: .cancel) { explained = true }
    }
  }

  // MARK: - Actions

  /// Removes the cloud copy. "Remove from Cloud Only" does exactly this, including
  /// downloading the media first so the device copy is complete before anything goes.
  @MainActor
  private func keepOnDevice() async {
    guard let context = memory.modelContext else { return }
    if memory.needsCloudBackup {
      // Never reached the server: nothing to delete, just stop it being uploaded.
      memory.keepLocalOnly = true
      try? context.save()
      revealLabelBriefly()
      return
    }
    isWorking = true
    defer { isWorking = false }
    do {
      try await MemoryService.deleteMemory(memory, scope: .remoteOnly, context: context)
      revealLabelBriefly()
    } catch {
      errorMessage = (error as? LocalizedError)?.errorDescription
        ?? "Check your connection and try again. Nothing was removed from the cloud."
    }
  }

  /// Uploads now. A failure leaves it queued (the arrow cloud) for the next drain.
  @MainActor
  private func backUp() async {
    guard let context = memory.modelContext else { return }
    memory.keepLocalOnly = false
    memory.needsCloudBackup = true
    try? context.save()
    isWorking = true
    defer { isWorking = false }
    await CloudBackupService.backUpNow(memory)
    revealLabelBriefly()
  }

  private func revealLabelBriefly() {
    labelTask?.cancel()
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showTransientLabel = true }
    labelTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.6))
      guard !Task.isCancelled else { return }
      withAnimation(.easeInOut(duration: 0.25)) { showTransientLabel = false }
    }
  }
}
