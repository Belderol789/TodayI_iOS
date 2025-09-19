import SwiftUI

struct PremiumMoodCard: ViewModifier {
  let color: Color
  let isPremium: Bool
  let scheme: ColorScheme
  
  func body(content: Content) -> some View {
    // Opacity tuning for light/dark
    let washHi  = scheme == .dark ? 0.18 : 0.14   // diagonal wash stronger in dark
    let washLo  = scheme == .dark ? 0.08 : 0.06
    let blobA   = scheme == .dark ? 0.22 : 0.16   // corner blobs
    let blobB   = scheme == .dark ? 0.12 : 0.10
    let strokeO = scheme == .dark ? 0.28 : 0.22
    
    let base = RoundedRectangle(cornerRadius: 16, style: .continuous)
    
    return content
      .background(
        ZStack {
          // Base card
          base.fill(Color(.secondarySystemBackground))
          
          if isPremium {
            // Diagonal mood wash
            base
              .fill(
                LinearGradient(
                  colors: [color.opacity(washHi), color.opacity(washLo)],
                  startPoint: .topLeading, endPoint: .bottomTrailing
                )
              )
              .blendMode(.overlay)
            
            // Soft corner blobs for depth
            base
              .fill(
                RadialGradient(
                  colors: [color.opacity(blobA), .clear],
                  center: .topLeading, startRadius: 0, endRadius: 280
                )
              )
              .blendMode(.plusLighter)
            
            base
              .fill(
                RadialGradient(
                  colors: [color.opacity(blobB), .clear],
                  center: .bottomTrailing, startRadius: 0, endRadius: 240
                )
              )
              .blendMode(.plusLighter)
            
            // Premium stroke (subtle)
            base
              .stroke(color.opacity(strokeO), lineWidth: 1)
          }
        }
      )
    // Outer shadow (kept subtle; only when premium)
      .shadow(color: isPremium ? color.opacity(0.12) : .clear, radius: isPremium ? 10 : 0, x: 0, y: 6)
  }
}

extension View {
  @inline(__always)
  func premiumMoodCard(color: Color, isPremium: Bool, scheme: ColorScheme) -> some View {
    modifier(PremiumMoodCard(color: color, isPremium: isPremium, scheme: scheme))
  }
}
