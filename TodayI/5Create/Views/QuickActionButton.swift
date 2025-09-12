//
//  QuickActionButton.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/13/25.
//

import SwiftUI
// MARK: - QuickActionButton (keeps your fixed background shape to avoid ShapeStyle error)

struct QuickActionButton: View {
  let title: String
  let systemImage: String
  let action: () -> Void
  let isEnabled: Bool
  var color: Color?
  
  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: systemImage)
          .imageScale(.medium)
        Text(title)
          .font(.subheadline.weight(.semibold))
          .multilineTextAlignment(.center)
      }
      .frame(width: 80, height: 80) // 👈 consistent square size
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .foregroundStyle(isEnabled ? (color ?? .accentColor) : .secondary)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(.secondarySystemBackground))
      )
      .overlay(
        Group {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(color ?? .accentColor, lineWidth: 1)
          if !isEnabled {
            VStack(spacing: 4) {
              Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(.secondary)
          }
        }
      )
    }
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1.0 : 0.55)
  }
}

#Preview("Enabled") {
  QuickActionButton(
    title: "Link", systemImage: "link",
    action: { /* add URL */ },
    isEnabled: true,
    color: Mood.sad.adaptiveColor
  )
}

#Preview("Disabled") {
  QuickActionButton(
    title: "Link", systemImage: "link",
    action: { /* add URL */ },
    isEnabled: false,
    color: Mood.sad.adaptiveColor
  )
}
