import SwiftUI
import StoreKit

struct PremiumView: View {
  
  @Environment(\.colorScheme) private var scheme
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var iap: IAPStore
  
  // Pull every mood's adaptive color
  private var palette: [Color] {
    // You can reorder for nicer hue flow if you want.
    // Example: [.happy, .surprise, .angry, .disgust, .neutral, .sad, .fear]
    Mood.allCases.map { $0.adaptiveColor }
  }
  
  // Convenience gradients
  private var bgGradient: LinearGradient {
    LinearGradient(
      colors: palette + [palette.first ?? .blue], // wrap to avoid hard stop
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
  
  private var stripeGradient: LinearGradient {
    LinearGradient(
      colors: palette,
      startPoint: .leading,
      endPoint: .trailing
    )
  }
  
  var body: some View {
    ZStack {
      // MULTI-MOOD BACKGROUND
      bgGradient
        .opacity(scheme == .dark ? 0.45 : 0.35)
        .ignoresSafeArea()
      // Subtle softening layer to keep text readable
        .overlay(
          Rectangle()
            .fill(.black.opacity(scheme == .dark ? 0.25 : 0.08))
            .ignoresSafeArea()
        )
      
      // Mood watermark layer
      VStack { watermarkBackground }
        .padding(.top, 80)   // keep it clear of the title a bit
        .allowsHitTesting(false)
      
      ScrollView {
        VStack(spacing: 24) {
          header
          featuresCard
          pricingButtons
        }
        .padding(.vertical, 24)
      }
    }
  }
  
  // MARK: - Sections
  
  private var header: some View {
    VStack(spacing: 10) {
      Text("Go Premium")
        .font(.largeTitle.bold())
        .foregroundStyle(stripeGradient)
        .overlay {
          // Gradient text
          LinearGradient(colors: palette, startPoint: .leading, endPoint: .trailing)
            .mask(Text("Go Premium").font(.largeTitle.bold()))
        }
      
      Text("Unlock multiple memories per day, premium feed flair, videos and galleries, and a monthly mood summary.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
      
      iconRibbon  // ← add here
    }
    .padding(.top, 8)
  }
  
  private var featuresCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      featureRow("More than one memory per day")
      featureRow("Premium look in the global feed")
      featureRow("Video and gallery posts")
      featureRow("Monthly mood summary")
      featureRow("More moods coming soon")
    }
    .padding(20)
    .background(
      // Soft glass card so the busy bg doesn’t fight the text
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.12))
        .background(
          // A faint multi-color border glow
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.clear)
            .overlay(
              RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(stripeGradient.opacity(0.35), lineWidth: 1)
            )
        )
    )
    .padding(.horizontal, 20)
  }
  
  var pricingButtons: some View {
    VStack(spacing: 12) {
      if let m = iap.monthly {
        Button("Start Monthly – \(m.priceString)") {
          Task { await iap.buy(m) }
        }
      }
      if let y = iap.yearly {
        let savings = savingsCopy(monthly: iap.monthly, yearly: iap.yearly)
        Button("Start Yearly – \(y.priceString)\(savings.map { " (\($0))" } ?? "")") {
          Task { await iap.buy(y) }
        }
      }
      
      Button("Restore Purchases") {
        Task { await iap.restore() }
      }
      
      if entitlements.isPremium {
        Text("You’re Premium ✅")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      
      // ── DEBUG ONLY CONTROLS ─────────────────────────────────────────────
#if DEBUG
      Divider().padding(.top, 8).opacity(0.2)
      
      HStack(spacing: 12) {
        Button {
          entitlements.isPremium = true
        } label: {
          Label("Debug: Grant Premium", systemImage: "wand.and.stars")
        }
        .buttonStyle(.borderedProminent)
        
        Button {
          entitlements.isPremium = false
        } label: {
          Label("Revoke", systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
      }
      .font(.footnote.weight(.semibold))
#endif
      // ───────────────────────────────────────────────────────────────────
    }
  }
  
  // MARK: - Helpers
  
  @MainActor
  func savingsCopy(monthly: Product?, yearly: Product?) -> String? {
    guard
      let m = monthly, let y = yearly,
      m.monthsInPeriod == 1, y.monthsInPeriod == 12
    else { return nil }
    
    let monthly12 = m.priceDouble * 12
    let diff = monthly12 - y.priceDouble
    guard diff > 0 else { return nil }
    
    let pct = (diff / monthly12) * 100.0
    let monthsFree = diff / m.priceDouble
    let label = (monthsFree >= 1.5 && monthsFree <= 2.5) ? "2 months free" : String(format: "Save %.0f%%", pct)
    return "~\(label)"
  }
  
  private func featureRow(_ text: String) -> some View {
    HStack(spacing: 10) {
      // Tiny multi-mood badge
      Circle()
        .fill(stripeGradient)
        .frame(width: 18, height: 18)
        .overlay(Image(systemName: "checkmark").font(.caption2).foregroundStyle(.white))
      Text(text)
        .foregroundStyle(.primary)
    }
    .font(.body.weight(.medium))
  }
  
  private var watermarkBackground: some View {
    // Light, low-contrast icon grid behind content
    let cols = Array(repeating: GridItem(.flexible(), spacing: 16), count: 5)
    
    return LazyVGrid(columns: cols, spacing: 16) {
      // Repeat to fill tall screens
      ForEach(0..<30, id: \.self) { i in
        let mood = Mood.allCases[i % Mood.allCases.count]
        mood.image
          .resizable()
          .renderingMode(.template)
          .scaledToFit()
          .padding(8)
          .foregroundStyle(mood.adaptiveColor.opacity(0.10))
          .frame(height: 28)
      }
    }
    .padding(.horizontal, 24)
    .opacity(0.8)
    .blur(radius: 0.5)
  }
  
  private var iconRibbon: some View {
    HStack(spacing: 12) {
      Spacer(minLength: 0)  // leading spacer ensures centering
      ForEach(Mood.allCases, id: \.self) { mood in
        ZStack {
          Circle()
            .fill(mood.adaptiveColor.opacity(0.18))
            .overlay(
              Circle().stroke(mood.adaptiveColor.opacity(0.35), lineWidth: 1)
            )
          
          mood.image
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .padding(6)
            .foregroundStyle(mood.adaptiveColor)
        }
        .frame(width: 36, height: 36)
      }
      Spacer(minLength: 0)  // trailing spacer ensures centering
    }
    .frame(maxWidth: .infinity) // let it fill horizontal space
  }
}
