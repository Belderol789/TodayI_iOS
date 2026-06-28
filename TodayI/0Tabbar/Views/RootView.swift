// MARK: - Root container with custom bar
import SwiftUI

struct RootView: View {
  @EnvironmentObject private var auth: AuthStore
  @State private var selection: AppTab = .home
  @State private var splashDone = false
  @Namespace private var tabNS

  var body: some View {
    Group {
      if auth.isSessionReady && splashDone {
        mainContent
      } else {
        SplashView()
          .task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            splashDone = true
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
        NotificationView(tabSelection: $selection)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      CustomTabBar(selection: $selection, namespace: tabNS)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
  }
}

// MARK: - Splash

private struct SplashView: View {
  private let mood: Mood = Mood.allCases.randomElement()!

  @State private var rotation: Double = 0
  @State private var iconScale: Double = 0.7
  @State private var titleOpacity: Double = 0

  var body: some View {
    ZStack {
      mood.adaptiveColor
        .ignoresSafeArea()

      // Soft radial glow behind the icon
      Circle()
        .fill(.white.opacity(0.12))
        .frame(width: 200, height: 200)
        .blur(radius: 40)
        .accessibilityHidden(true)

      VStack(spacing: 24) {
        mood.image
          .resizable()
          .scaledToFit()
          .frame(width: 80, height: 80)
          .rotationEffect(.degrees(rotation))
          .scaleEffect(iconScale)
          .accessibilityHidden(true)

        Text("TodayI")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(.white)
          .opacity(titleOpacity)
      }
    }
    .onAppear {
      withAnimation(.easeOut(duration: 0.5)) {
        iconScale = 1.0
        titleOpacity = 1.0
      }
      withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
        rotation = 360
      }
    }
  }
}
