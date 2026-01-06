import SwiftUI
import StoreKit

struct PremiumView: View {
  
  @Environment(\.colorScheme) private var scheme
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var iap: IAPStore
  
  private let privacyURL = URL(string: "https://github.com/KuzoStudiosPH/TodayI/wiki/Privacy-Policy")!
  private let appleTermsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
  
  private var palette: [Color] { Mood.allCases.map { $0.adaptiveColor } }
  
  private var bgGradient: LinearGradient {
    LinearGradient(
      colors: palette + [palette.first ?? .blue],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
  
  private var stripeGradient: LinearGradient {
    LinearGradient(colors: palette, startPoint: .leading, endPoint: .trailing)
  }
  
  var body: some View {
    ZStack {
      // MULTI-MOOD BACKGROUND (decorative)
      bgGradient
        .opacity(scheme == .dark ? 0.45 : 0.35)
        .ignoresSafeArea()
        .overlay(
          Rectangle()
            .fill(.black.opacity(scheme == .dark ? 0.25 : 0.08))
            .ignoresSafeArea()
        )
        .accessibilityHidden(true)
      
      // Mood watermark layer (decorative)
      VStack { watermarkBackground }
        .padding(.top, 80)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      
      ScrollView {
        VStack(spacing: 24) {
          header
          featuresCard
          pricingButtons
          legalLinks
        }
        .padding(.vertical, 24)
        .padding(.bottom, 24) // ✅ simple extra space
      }
      // Give the screen a sensible “container” label
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Premium options")
      .safeAreaPadding(.bottom, 24)
    }
  }
  
  // MARK: - Sections
  
  private var header: some View {
    VStack(spacing: 10) {
      // Gradient text is visual; provide a clean VO label
      Text("Go Premium")
        .font(.largeTitle.bold())
        .foregroundStyle(stripeGradient)
        .overlay {
          LinearGradient(colors: palette, startPoint: .leading, endPoint: .trailing)
            .mask(Text("Go Premium").font(.largeTitle.bold()))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Go Premium")
        .accessibilityAddTraits(.isHeader)
      
      Text("Unlock multiple memories per day, premium feed flair, videos and galleries, and a monthly mood summary.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .accessibilityLabel("Unlock multiple memories per day, premium feed flair, videos and galleries, and a monthly mood summary.")
      
      iconRibbon
        .accessibilityHidden(true) // decorative icons; features list explains benefits
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
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.12))
        .background(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.clear)
            .overlay(
              RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(stripeGradient.opacity(0.35), lineWidth: 1)
            )
        )
        .accessibilityHidden(true) // decorative shape/border
    )
    .padding(.horizontal, 20)
    // ✅ Make the whole card discoverable + readable like a list
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Premium features")
  }
  
  var pricingButtons: some View {
    VStack(spacing: 12) {
      
      SubscriptionButton(product: iap.monthly,
                         isYearly: false,
                         debugPriceOverride: nil) {
        Task { await iap.buy(iap.monthly!) }
      }
      // ✅ Ensure the button is understandable even if SubscriptionButton UI is complex
                         .accessibilityElement(children: .contain)
                         .accessibilityLabel(monthlyA11yLabel)
                         .accessibilityHint("Double tap to subscribe monthly.")
      
      SubscriptionButton(product: iap.yearly,
                         isYearly: true,
                         debugPriceOverride: nil) {
        Task { await iap.buy(iap.yearly!) }
      }
                         .accessibilityElement(children: .contain)
                         .accessibilityLabel(yearlyA11yLabel)
                         .accessibilityHint("Double tap to subscribe yearly.")
      
      Button("Restore Purchases") {
        Task { await iap.restore() }
      }
      .accessibilityLabel("Restore Purchases")
      .accessibilityHint("Restores purchases made with your Apple ID.")
      
      if entitlements.isPremium {
        Text("You’re Premium ✅")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityLabel("You are Premium.")
      }
      
#if DEBUG
      // debugPremium
#endif
    }
    .padding()
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Purchase options")
  }
  
  private var legalLinks: some View {
    HStack(spacing: 10) {
      Link("Privacy Policy", destination: privacyURL)
        .font(.footnote.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.white.opacity(scheme == .dark ? 0.10 : 0.60)))
        .buttonStyle(.plain)
        .accessibilityLabel("Privacy Policy")
        .accessibilityHint("Opens the privacy policy in your browser.")
      
      Link("Apple Terms of Service", destination: appleTermsURL)
        .font(.footnote.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.white.opacity(scheme == .dark ? 0.10 : 0.60)))
        .buttonStyle(.plain)
        .accessibilityLabel("Apple Terms of Use")
        .accessibilityHint("Opens Apple's standard end user license agreement.")
    }
    .padding(.horizontal, 20)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Legal links")
  }
  
  // MARK: - Helpers
  
  private var monthlyA11yLabel: String {
    // Best-effort: if product is nil (still loading), say so
    guard let p = iap.monthly else { return "Monthly subscription. Loading price." }
    // If you have localized price string helper, use it. Fallback:
    return "Monthly subscription. \(p.displayName). \(p.displayPrice)."
  }
  
  private var yearlyA11yLabel: String {
    guard let p = iap.yearly else { return "Yearly subscription. Loading price." }
    // Optional: add savings copy if you want
    let savings = savingsCopy(monthly: iap.monthly, yearly: iap.yearly)
    if let savings {
      return "Yearly subscription. \(p.displayName). \(p.displayPrice). \(savings)."
    } else {
      return "Yearly subscription. \(p.displayName). \(p.displayPrice)."
    }
  }
  
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
    return "\(label)"
  }
  
  private func featureRow(_ text: String) -> some View {
    HStack(spacing: 10) {
      Circle()
        .fill(stripeGradient)
        .frame(width: 18, height: 18)
        .overlay(Image(systemName: "checkmark").font(.caption2).foregroundStyle(.white))
        .accessibilityHidden(true) // don’t read “checkmark” etc.
      
      Text(text)
        .foregroundStyle(.primary)
    }
    .font(.body.weight(.medium))
    // ✅ Read each feature cleanly
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Feature: \(text)")
  }
  
  private var watermarkBackground: some View {
    let cols = Array(repeating: GridItem(.flexible(), spacing: 16), count: 5)
    
    return LazyVGrid(columns: cols, spacing: 16) {
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
      Spacer(minLength: 0)
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
        .accessibilityHidden(true) // decorative
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
  }
}
