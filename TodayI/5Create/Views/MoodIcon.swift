//
//  MoodIcon.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/13/25.
//

import SwiftUI

struct MoodIcon: View {
  let mood: Mood
  let size: CGFloat
  
  var body: some View {
    mood.image
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .foregroundStyle(mood.adaptiveColor)
  }
}

#Preview {
  MoodIcon(mood: .happy, size: 40)
}
