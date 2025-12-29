import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
  case home, calendar, create, notifications, global
  
  var id: String { rawValue }
  var systemImage: String {
    switch self {
    case .home:          return "house.fill"
    case .calendar:      return "calendar"
    case .create:        return "plus.circle.fill"
    case .global:        return "globe"
    case .notifications: return "bell.fill"
    }
  }
}
