//
//  PrivacyBadge.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/6/25.
//

import SwiftUI

import SwiftUI

struct PrivacyBadge: View {
  @Binding var isPublic: Bool
  @Environment(\.colorScheme) private var scheme
  
  var body: some View {
    Button {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        isPublic.toggle()
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: isPublic ? "globe.americas.fill" : "lock.fill")
          .font(.subheadline.weight(.semibold))
        Text(isPublic ? "Public" : "Private")
          .font(.subheadline.weight(.semibold))
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        Capsule().fill(isPublic ? Color.green : Color.gray)
      )
      .shadow(color: shadowColor, radius: 4, x: 0, y: 2)
      .scaleEffect(isPublic ? 1.05 : 1.0)
      .animation(.easeOut(duration: 0.15), value: isPublic)
    }
    .buttonStyle(.plain)
  }
  
  private var shadowColor: Color {
    scheme == .dark
    ? .white.opacity(0.25)   // light glow for dark backgrounds
    : .black.opacity(0.25)   // darker shadow for light backgrounds
  }
}

#Preview("PrivacyBadge States") {
  VStack(spacing: 20) {
    PrivacyBadge(isPublic: .constant(true))   // Always public
    PrivacyBadge(isPublic: .constant(false))  // Always private
  }
  .padding()
}

#Preview("Interactive") {
  StatefulPreviewWrapper(false) { binding in
    PrivacyBadge(isPublic: binding)
      .padding()
  }
}
