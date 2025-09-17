//
//  DateFormatter.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/5/25.
//

import Foundation

extension DateFormatter {
  static let shortDay: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "MMM d"
    return df
  }()
  
  static let timeFormatter: DateFormatter = {
    let df = DateFormatter()
    df.timeStyle = .short
    df.dateStyle = .none
    return df
  }()
  
  static let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()
  
}
