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
          HomeView()
        case .calendar:
          CalendarView(tabSelection: $selection) // your existing calendar
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
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        CustomTabBar(selection: $selection, namespace: tabNS)
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
      }
    }
  }
}
