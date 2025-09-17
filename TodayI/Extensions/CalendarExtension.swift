//
//  CalendarExtension.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/6/25.
//

import Foundation

extension Calendar {
  static var gregorianLocal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .current
    return c
  }
}

