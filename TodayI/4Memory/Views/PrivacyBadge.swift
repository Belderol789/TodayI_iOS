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
  /// Icon only, no "Public"/"Private" label — for tight spots like the Create
  /// screen's navigation bar, where the globe/padlock has to carry the meaning.
  var compact: Bool = false
  @Environment(\.colorScheme) private var scheme

  /// Compact mode shows its word only just after a toggle, then collapses back to
  /// the icon. An icon-only switch leaves people guessing which state they just
  /// chose; a permanent label doesn't fit the navigation bar. This says it, briefly.
  @State private var showTransientLabel = false
  @State private var labelTask: Task<Void, Never>?

  private var transientLabel: String { isPublic ? "Global" : "Personal" }

  var body: some View {
    Button {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        isPublic.toggle()
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: isPublic ? "globe.americas.fill" : "lock.fill")
          .font(.subheadline.weight(.semibold))
        if !compact {
          Text(isPublic ? "Public" : "Private")
            .font(.subheadline.weight(.semibold))
        } else if showTransientLabel {
          Text(transientLabel)
            .font(.subheadline.weight(.semibold))
            .fixedSize()
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, compact ? 8 : 10)
      .padding(.vertical, 6)
      .background(
        Capsule().fill(isPublic ? Color.green : Color.gray)
      )
      .shadow(color: shadowColor, radius: 4, x: 0, y: 2)
      .scaleEffect(isPublic ? 1.05 : 1.0)
      .animation(.easeOut(duration: 0.15), value: isPublic)
    }
    .buttonStyle(.plain)
    .onChange(of: isPublic) { _, _ in
      guard compact else { return }
      revealLabelBriefly()
    }
    .onDisappear { labelTask?.cancel() }
    // Carries the meaning when `compact` hides the word. Callers that set their own
    // label (MemoryRow) still override these.
    .accessibilityLabel("Privacy")
    .accessibilityValue(isPublic ? "Public" : "Private")
    .accessibilityHint(isPublic ? "Double tap to make this private."
                                : "Double tap to make this public.")
  }

  /// Slides the word in, holds, slides it out. Re-toggling restarts the timer
  /// rather than stacking hides on top of each other.
  private func revealLabelBriefly() {
    labelTask?.cancel()
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      showTransientLabel = true
    }
    labelTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.6))
      guard !Task.isCancelled else { return }
      withAnimation(.easeInOut(duration: 0.25)) {
        showTransientLabel = false
      }
    }
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
