//
//  CalendarExtension.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/6/25.
//

import Foundation

extension Calendar {
  static let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!    // force UTC
    return c
  }()
}
