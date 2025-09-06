//
//  ArrayExtension.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/5/25.
//

import SwiftUI

extension Array where Element == Mood {
  /// Top→bottom gradient that adapts automatically.
  func adaptiveGradient(axis: (start: UnitPoint, end: UnitPoint) = (.top, .bottom)) -> LinearGradient {
    let colors = (isEmpty ? [.clear] : map { $0.adaptiveColor })
    return LinearGradient(colors: colors, startPoint: axis.start, endPoint: axis.end)
  }
}
