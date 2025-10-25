import StoreKit

@MainActor
final class IAPStore: ObservableObject {
  @Published var monthly: Product?
  @Published var yearly: Product?
  @Published var isLoading = false
  @Published var errorMessage: String?
  
  private unowned let entitlements: EntitlementStore
  
  init(entitlements: EntitlementStore) {
    self.entitlements = entitlements
    Task {
      await refreshProducts()
    }
  }
  
  func refreshProducts() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let ids = [IAP.monthlyID, IAP.yearlyID]
      let products = try await Product.products(for: ids)
      for p in products {
        switch p.id {
        case IAP.monthlyID: monthly = p
        case IAP.yearlyID:  yearly  = p
        default: break
        }
      }
    } catch {
      errorMessage = "Failed to load products: \(error)"
    }
  }
  
  func buy(_ product: Product) async {
    isLoading = true
    defer { isLoading = false }
    do {
      let result = try await product.purchase()
      switch result {
      case .success(let verification):
        if case .verified(let transaction) = verification {
          await transaction.finish()
          await entitlements.refresh()  // ← update entitlement truth
        }
      case .userCancelled, .pending:
        break
      @unknown default:
        break
      }
    } catch {
      errorMessage = "Purchase failed: \(error)"
    }
  }
  
  func restore() async {
    isLoading = true
    defer { isLoading = false }
    do {
      try await AppStore.sync()
      await entitlements.refresh()
    } catch {
      errorMessage = "Restore failed: \(error)"
    }
  }
}

// Price helpers
extension Product {
  var priceString: String {
    price.formatted(.currency(code: priceFormatStyle.currencyCode))
  }
  var monthsInPeriod: Int {
    guard let period = self.subscription?.subscriptionPeriod else { return 0 }
    switch (period.unit, period.value) {
    case (.month, let v): return v
    case (.year,  let v): return v * 12
    case (.week,  let v): return max(1, v) / 4
    case (.day,   _):     return 0
    @unknown default:     return 0
    }
  }
  var priceDouble: Double { NSDecimalNumber(decimal: price).doubleValue }
}
