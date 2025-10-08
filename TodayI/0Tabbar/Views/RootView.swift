// MARK: - Root container with custom bar
import SwiftUI

struct RootView: View {
  @State private var selection: AppTab = .home
  @Namespace private var tabNS
  
  var body: some View {
    NavigationStack {
      ZStack {
        switch selection {
        case .home:
          Text("🏠 Home").font(.largeTitle.bold())
        case .calendar:
          CalendarView() // your existing calendar
        case .create:
          CreateMemoryView()
        case .global:
          GlobalFeedView(
            tabSelection: $selection,
            day: Date()
          )
        case .notifications:
          Text("🔔 Notifications").font(.largeTitle.bold())
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        CustomTabBar(selection: $selection, namespace: tabNS)
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
      }
    }
  }
}
