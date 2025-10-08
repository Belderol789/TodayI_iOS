import SwiftUI

struct PremiumMoodCard: ViewModifier {
  let color: Color
  let isPremium: Bool
  let scheme: ColorScheme
  
  func body(content: Content) -> some View {
    // Much softer opacities for light/dark
    let washHi  = scheme == .dark ? 0.10 : 0.08   // diagonal wash
    let washLo  = scheme == .dark ? 0.05 : 0.04
    let blobA   = scheme == .dark ? 0.12 : 0.08   // corner blobs
    let blobB   = scheme == .dark ? 0.07 : 0.05
    let strokeO = scheme == .dark ? 0.16 : 0.12   // outline stroke
    
    let base = RoundedRectangle(cornerRadius: 16, style: .continuous)
    
    return content
      .background(
        ZStack {
          // Base card
          base.fill(Color(.secondarySystemBackground))
          
          if isPremium {
            // Diagonal mood wash (much duller)
            base.fill(
              LinearGradient(
                colors: [color.opacity(washHi), color.opacity(washLo)],
                startPoint: .topLeading, endPoint: .bottomTrailing
              )
            )
            .blendMode(.overlay)
            
            // Corner blobs (more muted)
            base.fill(
              RadialGradient(
                colors: [color.opacity(blobA), .clear],
                center: .topLeading, startRadius: 0, endRadius: 280
              )
            )
            .blendMode(.plusLighter)
            
            base.fill(
              RadialGradient(
                colors: [color.opacity(blobB), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 240
              )
            )
            .blendMode(.plusLighter)
            
            // Premium stroke (lighter)
            base.stroke(color.opacity(strokeO), lineWidth: 1)
          }
        }
      )
    // Very subtle shadow
      .shadow(color: isPremium ? color.opacity(0.08) : .clear,
              radius: isPremium ? 6 : 0, x: 0, y: 3)
  }
}

extension View {
  @inline(__always)
  func premiumMoodCard(color: Color, isPremium: Bool, scheme: ColorScheme) -> some View {
    modifier(PremiumMoodCard(color: color, isPremium: isPremium, scheme: scheme))
  }
}
