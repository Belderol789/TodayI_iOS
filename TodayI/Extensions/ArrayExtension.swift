//
//  ArrayExtension.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/5/25.
//

import SwiftUI

extension Array where Element == Mood {
  func gradient(for scheme: ColorScheme) -> LinearGradient {
    let colors = self.map { $0.color(for: scheme) }
    return LinearGradient(colors: colors.isEmpty ? [.gray] : colors,
                          startPoint: .top,
                          endPoint: .bottom)
  }
}
