//
//  ColorExtension.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/6/25.
//

import SwiftUI

extension Color {
  var isDark: Bool {
    let ui = UIColor(self)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    let luminance = 0.299*r + 0.587*g + 0.114*b
    return luminance < 0.5
  }
}
