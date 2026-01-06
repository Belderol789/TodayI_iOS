import SwiftUI
import StoreKit

struct SubscriptionButton: View {
  let product: Product?          // ← now optional
  let isYearly: Bool
  let debugPriceOverride: String?
  let action: () -> Void
  
  private var displayPrice: String {
    if let override = debugPriceOverride { return override }
    if let product = product { return product.priceString }
    return "…"
  }
  
  // ✅ Accessibility helpers
  private var planName: String { isYearly ? "Yearly Premium" : "Monthly Premium" }
  
  private var badgeText: String? {
    guard isYearly else { return nil }
    return "Best value, 2 months free"
  }
  
  private var isLoading: Bool {
    // if neither product nor debug price exists, we’re effectively loading
    product == nil && debugPriceOverride == nil
  }
  
  private var a11yLabel: String {
    if let badgeText {
      return "\(planName). \(badgeText)."
    } else {
      return "\(planName)."
    }
  }
  
  private var a11yValue: String {
    if isLoading { return "Price loading" }
    return displayPrice
  }
  
  private var a11yHint: String {
    if isLoading { return "Please wait for pricing to load." }
    return "Double tap to purchase."
  }
  
  var body: some View {
    Button {
      if product != nil { action() }
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        
        if isYearly {
          Text("BEST VALUE – 2 Months Free")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor)
            .clipShape(Capsule())
            .accessibilityHidden(true) // ✅ don’t read badge twice
        }
        
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(isYearly ? "Yearly Premium" : "Monthly Premium")
              .font(.headline)
              .foregroundColor(.primary)
            
            Text(displayPrice)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          
          Spacer()
          
          Image(systemName: "chevron.right")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true) // ✅ decorative
        }
      }
      .padding()
      .background(
        RoundedRectangle(cornerRadius: 14)
          .fill(isYearly
                ? Color.accentColor.opacity(0.12)
                : Color(.systemBackground).opacity(0.7)
               )
          .shadow(color: .black.opacity(isYearly ? 0.15 : 0.05),
                  radius: isYearly ? 4 : 2,
                  x: 0, y: 2)
      )
    }
    .buttonStyle(.plain)
    .disabled(product == nil && debugPriceOverride == nil)
    
    // ✅ Make it read as one clean element
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(a11yLabel)
    .accessibilityValue(a11yValue)
    .accessibilityHint(a11yHint)
    
    // Optional: announce disabled state more clearly
    .accessibilityAddTraits(.isButton)
  }
}
