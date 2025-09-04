//
//  CalendarModel.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/3/25.
//

import Foundation
import SwiftData

@Model
final class DateModel {
  @Attribute(.unique) var date: Date
  private(set) var moodRaws: [String]
  
  @Transient
  var moods: [Mood] {
    get { moodRaws.compactMap(Mood.init(rawValue:)) }
    set { moodRaws = newValue.map(\.rawValue) }
  }
  
  init(date: Date, moods: [Mood] = []) {
    self.date = Calendar.current.startOfDay(for: date)  // <- normalize
    self.moodRaws = moods.map(\.rawValue)
  }
}

extension DateModel {
  func dateOnly(_ cal: Calendar) -> Date {
    cal.startOfDay(for: self.date)
  }
}
