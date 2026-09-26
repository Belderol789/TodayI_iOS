import SwiftUI
import StoreKit

struct PremiumView: View {
  
  @Environment(\.colorScheme) private var scheme
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var iap: IAPStore
  @EnvironmentObject private var auth: AuthStore

  @State private var showAuth = false

  /// Premium's headline benefit is cloud backup, and a backup is only as durable as the
  /// identity it's filed under. An anonymous user's uid lives in the Keychain: it
  /// survives deleting the app, but not a new device, a wiped Keychain or a restore
  /// without it. When it's gone the backup sits in Firestore under an identity nobody
  /// can authenticate as — unreachable, permanently.
  ///
  /// So this is a hard gate rather than a nudge. Everything else in the app works
  /// anonymously on purpose; this is the one purchase that is meaningless without an
  /// account, and letting someone pay for it first is selling them something that can
  /// silently evaporate.
  private var needsAccount: Bool { auth.isGuest }
  
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
          // A subscriber doesn't need a sales pitch — show them what they're on.
          if entitlements.isPremium {
            subscriptionCard
          } else {
            pricingButtons
          }
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
    .sheet(isPresented: $showAuth) {
      NavigationStack { AuthView() }
    }
  }
  
  // MARK: - Sections
  
  private var headline: String {
    entitlements.isPremium ? "You're Premium" : "Go Premium"
  }

  private var subhead: String {
    entitlements.isPremium
    ? "Your journal is backed up, with multiple memories per day, premium feed flair, videos and galleries, and a monthly mood summary — all unlocked."
    : "Back your journal up to the cloud, and unlock multiple memories per day, premium feed flair, videos and galleries, and a monthly mood summary."
  }

  private var header: some View {
    VStack(spacing: 10) {
      // Gradient text is visual; provide a clean VO label
      Text(headline)
        .font(.largeTitle.bold())
        .foregroundStyle(stripeGradient)
        .overlay {
          LinearGradient(colors: palette, startPoint: .leading, endPoint: .trailing)
            .mask(Text(headline).font(.largeTitle.bold()))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headline)
        .accessibilityAddTraits(.isHeader)

      Text(subhead)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .accessibilityLabel(subhead)
      
      iconRibbon
        .accessibilityHidden(true) // decorative icons; features list explains benefits
    }
    .padding(.top, 8)
  }
  
  private var featuresCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      // First, because it's the reason the sign-in gate exists and the only feature
      // here that protects something the user would be upset to lose.
      featureRow("Your journal backed up to the cloud")
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
  
  // MARK: - Subscription status (shown instead of pricing when already Premium)

  /// The StoreKit entitlement backing Premium, if there is one. Premium can also be
  /// on without a purchase (device trial, or the entitlement override in
  /// `EntitlementStore`), in which case there are no dates to show and the card says
  /// so rather than inventing a renewal.
  private var activeSubscription: Entitlement? {
    entitlements.active.first {
      $0.productId == IAP.monthlyID || $0.productId == IAP.yearlyID
    }
  }

  private var isYearlyPlan: Bool { activeSubscription?.productId == IAP.yearlyID }

  private var subscriptionProduct: Product? {
    guard activeSubscription != nil else { return nil }
    return isYearlyPlan ? iap.yearly : iap.monthly
  }

  private var daysLeft: Int? {
    guard let expiry = activeSubscription?.expiresAt else { return nil }
    guard let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    else { return nil }
    return max(0, days)
  }

  var subscriptionCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(activeSubscription == nil ? "Premium" : (isYearlyPlan ? "Yearly plan" : "Monthly plan"))
          .font(.headline)
        Spacer()
        Text("Active")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(Capsule().fill(.green.opacity(0.22)))
      }

      if activeSubscription != nil {
        if let product = subscriptionProduct {
          statusRow("Price", "\(product.displayPrice) / \(isYearlyPlan ? "year" : "month")")
        }
        if let days = daysLeft {
          statusRow("Days left", days == 1 ? "1 day" : "\(days) days")
        }
        if let expiry = activeSubscription?.expiresAt {
          // "Ends", not "Renews" — the entitlement carries an expiry date but not
          // whether auto-renew is still on, so claiming it will renew could be wrong
          // for someone who has already cancelled.
          statusRow("Current period ends",
                    expiry.formatted(date: .abbreviated, time: .omitted))
          Text("Renews automatically unless you cancel.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else {
        Text("Premium is active on this device but isn't linked to an App Store subscription, so there's no renewal date to show.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Button {
        Task { await openManageSubscriptions() }
      } label: {
        Text(activeSubscription == nil ? "Manage Subscriptions" : "Manage or Cancel")
          .font(.subheadline.weight(.semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .background(Capsule().fill(Color.primary.opacity(0.12)))
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens your Apple subscription settings.")

      Button("Restore Purchases") {
        Task { await iap.restore() }
      }
      .font(.footnote)
      .frame(maxWidth: .infinity)
      .accessibilityHint("Restores purchases made with your Apple ID.")
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.12))
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(stripeGradient.opacity(0.35), lineWidth: 1)
        )
        .accessibilityHidden(true)
    )
    .padding(.horizontal, 20)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Your subscription")
  }

  private func statusRow(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(value).fontWeight(.semibold)
    }
    .font(.subheadline)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(label): \(value)")
  }

  /// Apple's own sheet, so cancelling happens where Apple requires it.
  /// Falls back to the App Store subscriptions page if no scene is available.
  @MainActor
  private func openManageSubscriptions() async {
    let scene = UIApplication.shared.connectedScenes
      .first { $0.activationState == .foregroundActive } as? UIWindowScene
    if let scene {
      do {
        try await AppStore.showManageSubscriptions(in: scene)
        return
      } catch {
        print("⚠️ showManageSubscriptions failed:", error)
      }
    }
    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
      await UIApplication.shared.open(url)
    }
  }

  /// Shown above the prices for anonymous users, so the sign-in sheet isn't a surprise.
  private var accountRequiredNotice: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "key.fill")
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.9))
      VStack(alignment: .leading, spacing: 3) {
        Text("Sign in first")
          .font(.subheadline.weight(.semibold))
        Text("Premium backs your journal up to the cloud. Without an account that backup is tied to this device — it can't follow you to a new phone.")
          .font(.caption)
          .opacity(0.9)
      }
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.white.opacity(0.16))
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Sign in required. Premium backs your journal up to the cloud, and without an account that backup is tied to this device.")
  }

  var pricingButtons: some View {
    VStack(spacing: 12) {
      
      if needsAccount { accountRequiredNotice }

      SubscriptionButton(product: iap.monthly,
                         isYearly: false,
                         debugPriceOverride: nil) {
        guard !needsAccount else { showAuth = true; return }
        guard let product = iap.monthly else { return }
        Task { await iap.buy(product) }
      }
      // ✅ Ensure the button is understandable even if SubscriptionButton UI is complex
                         .accessibilityElement(children: .contain)
                         .accessibilityLabel(monthlyA11yLabel)
                         .accessibilityHint("Double tap to subscribe monthly.")
      
      SubscriptionButton(product: iap.yearly,
                         isYearly: true,
                         debugPriceOverride: nil) {
        guard !needsAccount else { showAuth = true; return }
        guard let product = iap.yearly else { return }
        Task { await iap.buy(product) }
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
