//
//  DateExtension.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/3/25.
//

import Foundation

extension Date {
  
  func formatted(_ format: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: self)
  }
  
  /// Returns the day-of-month as a string (e.g. "3", "24").
  var dayString: String {
    String(Calendar.current.component(.day, from: self))
  }
  
  var startOfDay: Date {
    Calendar.current.startOfDay(for: self)
  }
  
  var startOfDayUTC: Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    return cal.startOfDay(for: self)
  }
  
  /// Returns a full, localized description of the date (e.g. "Wednesday, September 3, 2025").
  var accessibilityLabel: String {
    let df = DateFormatter()
    df.dateStyle = .full
    return df.string(from: self)
  }
  
  var year: Int { Calendar.current.component(.year, from: self) }
  var month: Int { Calendar.current.component(.month, from: self) }
  func startOfMonth(using calendar: Calendar = .current) -> Date {
    let comps = calendar.dateComponents([.year, .month], from: self)
    return calendar.date(from: comps)!
  }
}
