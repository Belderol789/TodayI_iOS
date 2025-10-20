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
  
  var today: Date {
    Calendar.current.startOfDay(for: self)
  }
  
  func startOfDay(in tz: TimeZone = .current) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.startOfDay(for: self)
  }
  
  func dayBounds(in tz: TimeZone = .current) -> (start: Date, end: Date) {
    let start = startOfDay(in: tz)
    let end = Calendar.gregorianLocal.date(byAdding: .day, value: 1, to: start)!
    return (start, end)
  }

  func formattedDayKeyLocal(in tz: TimeZone = .current) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let comps = cal.dateComponents([.year, .month, .day], from: self)
    return String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
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
