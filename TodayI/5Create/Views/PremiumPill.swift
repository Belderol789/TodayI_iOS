import SwiftUI

struct PremiumPill: View {
  let isPremium: Bool
  var onTap: (() -> Void)? = nil
  var haptics: Bool = true
  
  var body: some View {
    Button {
      if haptics { triggerHaptic() }
      //onTap?()
    } label: {
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
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .accessibilityLabel(isPremium ? "Premium" : "Free")
      .accessibilityAddTraits(.isButton)
    }
    .buttonStyle(PillPressStyle())
  }
  
  private func triggerHaptic() {
#if os(iOS)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
  }
}

/// Subtle press animation (scale + fade) without changing layout
private struct PillPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
      .opacity(configuration.isPressed ? 0.85 : 1.0)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

#Preview("Premium") {
  PremiumPill(isPremium: true) {
    print("Tapped premium")
  }
  .padding()
  .previewLayout(.sizeThatFits)
}

#Preview("Free") {
  PremiumPill(isPremium: false) {
    print("Tapped free")
  }
  .padding()
  .previewLayout(.sizeThatFits)
}
