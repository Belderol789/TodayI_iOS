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
    return "…" // fallback placeholder
  }
  
  var body: some View {
    Button {
      if product != nil { action() }   // prevent accidental purchase without a product
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        
        // Badge for yearly
        if isYearly {
          Text("BEST VALUE – 2 Months Free")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor)
            .clipShape(Capsule())
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
    .disabled(product == nil && debugPriceOverride == nil) // disables only when no real or debug value
  }
}
