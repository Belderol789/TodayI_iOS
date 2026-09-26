//
//  MaintenanceGate.swift
//  TodayI
//
//  A kill switch for the whole app, toggled from the Firebase console.
//

import Foundation
import FirebaseRemoteConfig
import SwiftUI

/// Reads the maintenance flag from Remote Config and exposes it to the UI.
///
/// Remote Config rather than a Firestore document on purpose: it is free (no read is
/// billed, unlike a `config/app` doc read on every launch by every user), it needs no
/// security rule, and it has a console toggle already built for exactly this.
///
/// **Fails open, always.** Every failure path — no network, a fetch error, a malformed
/// value, Firebase not reachable — leaves the app usable. A maintenance screen exists to
/// stop people using a broken backend; locking someone out of their journal because
/// their train went into a tunnel would be a far worse bug than the one it's guarding.
@MainActor
final class MaintenanceGate: ObservableObject {

  /// True only when the console explicitly says so and the fetch succeeded.
  @Published private(set) var isActive = false
  @Published private(set) var message = MaintenanceGate.fallbackMessage
  @Published private(set) var allowsRetry = true

  static let fallbackMessage =
    "TodayI is down for a short while so we can fix something. Your entries are safe on this device — nothing has been lost."

  private enum Key {
    static let enabled = "maintenance_enabled"
    static let message = "maintenance_message"
  }

  private let config = RemoteConfig.remoteConfig()

  init() {
    let settings = RemoteConfigSettings()
    // 12 hours is the default and far too slow for a switch you flip during an incident.
    // Debug refetches every time so the toggle can actually be tested.
#if DEBUG
    settings.minimumFetchInterval = 0
#else
    settings.minimumFetchInterval = 300
#endif
    config.configSettings = settings
    config.setDefaults([
      Key.enabled: false as NSObject,
      Key.message: MaintenanceGate.fallbackMessage as NSObject
    ])
  }

  /// Fetches and applies the current values. Safe to call repeatedly — call it on launch
  /// and on every foreground, so a session that started before the switch was flipped
  /// still picks it up without the user relaunching.
  func refresh() async {
    do {
      try await config.fetchAndActivate()
      let enabled = config[Key.enabled].boolValue
      let remoteMessage = config[Key.message].stringValue
      isActive = enabled
      message = remoteMessage.isEmpty ? Self.fallbackMessage : remoteMessage
      if enabled { print("🚧 Maintenance mode active") }
    } catch {
      // Deliberately silent to the user, and deliberately non-blocking.
      print("⚠️ Remote Config fetch failed, staying open:", error)
      isActive = false
    }
  }
}

// MARK: - Screen

struct MaintenanceView: View {
  @EnvironmentObject private var gate: MaintenanceGate
  @State private var isRetrying = false

  var body: some View {
    VStack(spacing: 22) {
      Spacer()

      Image(systemName: "wrench.and.screwdriver.fill")
        .font(.system(size: 46))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      Text("Back soon")
        .font(.title.weight(.bold))

      Text(gate.message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)

      Spacer()

      Button {
        isRetrying = true
        Task {
          await gate.refresh()
          isRetrying = false
        }
      } label: {
        if isRetrying {
          ProgressView()
        } else {
          Text("Check again").font(.subheadline.weight(.semibold))
        }
      }
      .buttonStyle(.bordered)
      .disabled(isRetrying)
      .padding(.bottom, 40)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
  }
}
