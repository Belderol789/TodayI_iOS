import SwiftUI

struct PremiumPill: View {
  let isPremium: Bool
  var onTap: (() -> Void)? = nil
  var haptics: Bool = true

  private var moodGradient: LinearGradient {
    LinearGradient(colors: Mood.allCases.map(\.adaptiveColor), startPoint: .leading, endPoint: .trailing)
  }

  var body: some View {
    Button {
      if haptics { triggerHaptic() }
      onTap?()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "star.fill")
        Text(isPremium ? "Premium" : "Upgrade")
          .font(.caption.weight(.semibold))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .foregroundStyle(isPremium ? .white : Color(.label))
      .background(
        Capsule()
          .fill(isPremium ? AnyShapeStyle(moodGradient) : AnyShapeStyle(Color(.tertiarySystemFill)))
      )
      .overlay(
        Capsule()
          .stroke(isPremium ? Color.clear : Color(.separator), lineWidth: 0.5)
      )
      .contentShape(Capsule())
      .accessibilityLabel(isPremium ? "Premium active" : "Upgrade to Premium")
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
