//
//  NotificationPermissionBanner.swift
//  TodayI
//

import SwiftUI
import UserNotifications

/// Shown at the top of the Notifications tab until notifications are allowed.
///
/// The only other place the app asked for permission was the one-time prompt after a
/// first post — decline it, or miss it, and there was no way back inside the app. This
/// covers both states iOS can be in: never asked (we can show the system prompt
/// ourselves) and denied (iOS won't show the prompt again, so the only route is the
/// app's page in Settings). Once allowed it renders nothing.
struct NotificationPermissionBanner: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var status: UNAuthorizationStatus?
  @State private var isRequesting = false

  var body: some View {
    // A VStack, not a Group: with nothing to show, a Group's only child is EmptyView,
    // and SwiftUI never runs .task or .onChange on an EmptyView — so the status was
    // never loaded and the card could never appear. A zero-height spacer below keeps
    // a real view in the hierarchy at all times.
    VStack(spacing: 0) {
      switch status {
      case .notDetermined:
        card(title: "Turn on notifications",
             message: "Get a gentle nudge to journal each evening, and hear when someone likes or replies to your posts.",
             action: "Turn On",
             icon: "bell.badge") {
          Task { await requestPermission() }
        }
      case .denied:
        card(title: "Notifications are off",
             message: "Turn them on in Settings to get your evening reminder and replies to your posts.",
             action: "Open Settings",
             icon: "bell.slash") {
          openSettings()
        }
      default:
        // Allowed (or still loading): nothing to ask for.
        Color.clear.frame(height: 0)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: status)
    .task { await refresh() }
    // Coming back from Settings is the moment a denied permission may have flipped.
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await refresh() } }
    }
  }

  // MARK: - Actions

  private func refresh() async {
    status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  /// Uses `NotificationManager.configure()` rather than asking directly, so a grant also
  /// registers for remote notifications — that's what delivers the APNs token and
  /// releases the queued topic subscriptions. Asking on its own would allow banners but
  /// leave every push topic unsubscribed until the next launch.
  private func requestPermission() async {
    isRequesting = true
    defer { isRequesting = false }
    _ = await NotificationManager.shared.configure()
    await refresh()
  }

  private func openSettings() {
    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  // MARK: - Layout

  private func card(title: String,
                    message: String,
                    action: String,
                    icon: String,
                    perform: @escaping () -> Void) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Button(action: perform) {
          if isRequesting {
            ProgressView()
          } else {
            Text(action).font(.subheadline.weight(.semibold))
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isRequesting)
        .padding(.top, 4)
      }
      Spacer(minLength: 0)
    }
    .padding(14)
    .background(Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .padding(.horizontal)
    .padding(.top, 8)
    .transition(.opacity.combined(with: .move(edge: .top)))
    .accessibilityElement(children: .combine)
  }
}
