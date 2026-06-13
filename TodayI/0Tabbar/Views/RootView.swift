// MARK: - Root container with custom bar
import SwiftUI

struct RootView: View {
  @EnvironmentObject private var auth: AuthStore
  @State private var selection: AppTab = .home
  @Namespace private var tabNS

  var body: some View {
    Group {
      if auth.isSessionReady {
        mainContent
      } else {
        // Shown while Firebase auth resolves on cold launch.
        // Uses an explicit gradient so it is never confused with a black screen,
        // even on OLED devices in dark mode where systemBackground = #000000.
        ZStack {
          LinearGradient(
            colors: [Color.indigo.opacity(0.85), Color.purple.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          .ignoresSafeArea()

          VStack(spacing: 20) {
            Image(systemName: "sun.max.fill")
              .font(.system(size: 56, weight: .semibold))
              .foregroundStyle(.yellow)
              .shadow(color: .yellow.opacity(0.6), radius: 12)

            Text("TodayI")
              .font(.largeTitle.weight(.bold))
              .foregroundStyle(.white)

            ProgressView()
              .progressViewStyle(.circular)
              .tint(.white)
              .scaleEffect(1.3)
              .padding(.top, 8)
          }
        }
      }
    }
  }

  private var mainContent: some View {
    ZStack {
      switch selection {
      case .home:
        HomeView()
      case .calendar:
        CalendarView(tabSelection: $selection)
      case .create:
        CreateMemoryView()
      case .global:
        GlobalFeedView(
          tabSelection: $selection,
          day: Date()
        )
      case .notifications:
        NotificationView()
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      CustomTabBar(selection: $selection, namespace: tabNS)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
  }
}
