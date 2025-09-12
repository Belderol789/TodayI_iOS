//
//  PremiumPill.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/13/25.
//

import SwiftUI

struct PremiumPill: View {
  let isPremium: Bool
  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: isPremium ? "star.fill" : "person.fill")
      Text(isPremium ? "Premium" : "Free")
        .font(.caption.weight(.semibold))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(isPremium ? Color.yellow.opacity(0.25) : Color.gray.opacity(0.15))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(isPremium ? Color.yellow.opacity(0.5) : Color.gray.opacity(0.25), lineWidth: 1)
    )
  }
}

#Preview("Premium") {
  PremiumPill(isPremium: true)
}

#Preview("Free") {
  PremiumPill(isPremium: false)
}
