// CalendarInsets.swift
import SwiftUI

private struct CalendarInsetsKey: EnvironmentKey {
  static let defaultValue = EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16)
}

extension EnvironmentValues {
  var calendarInsets: EdgeInsets {
    get { self[CalendarInsetsKey.self] }
    set { self[CalendarInsetsKey.self] = newValue }
  }
}
