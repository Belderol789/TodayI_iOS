//
//  TabButton.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/7/25.
//

import SwiftUI

// MARK: - Tab Button

struct TabButton: View {
  let tab: AppTab
  let isSelected: Bool
  let namespace: Namespace.ID
  let action: () -> Void
  @Environment(\.colorScheme) private var scheme
  
  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: tab.systemImage)
          .font(.system(size: 16, weight: .semibold))
      }
      .padding(.horizontal, isSelected ? 12 : 0)
      .padding(.vertical, 8)
      .frame(height: 36)
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .foregroundStyle(isSelected ? .primary : .secondary)
      .background(
        ZStack {
          if isSelected {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(selectionFill)
              .matchedGeometryEffect(id: "pill", in: namespace)
          }
        }
      )
    }
    .buttonStyle(.plain)
  }
  
  private var selectionFill: some ShapeStyle {
    scheme == .dark
    ? Color.white.opacity(0.10)
    : Color.black.opacity(0.06)
  }
}
