//
//  DateView.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/3/25.
//

import SwiftUI
import SwiftData

struct DateView: View {
  @Bindable var model: DateModel
  var cornerRadius: CGFloat = 12
  
  var body: some View {
    ZStack {
      // Background with glow
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(model.moods.last?.color ?? .gray)
        .shadow(color: (model.moods.last?.color ?? .gray).opacity(0.6), radius: 6)   // soft glow
        .shadow(color: (model.moods.last?.color ?? .gray).opacity(0.4), radius: 12)  // extended glow
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
      
      Text(model.date.dayString)
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .shadow(radius: 1, x: 0, y: 1) // text lift
    }
    .aspectRatio(1, contentMode: .fit)
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    .accessibilityLabel("\(model.date.accessibilityLabel), moods: \(model.moods.map(\.rawValue).joined(separator: ", "))")
  }
}

#Preview {
  DateView(model: DateModel(date: .now, moods: [.happy]))
    .padding()
    .frame(width: 80)
}
