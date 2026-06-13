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
    print("🛒 IAPStore.init()")
    
    Task {
      await withTimeout(seconds: 8) {
        await self.refreshProducts(reason: "init")
      }
    }
  }
  
  // MARK: - Refresh products
  func refreshProducts(reason: String = "manual") async {
    print("\n🔄 IAPStore.refreshProducts(reason: \(reason))")
    
    isLoading = true
    defer { isLoading = false }
    
    let ids = [IAP.monthlyID, IAP.yearlyID]
    print("🔍 Requesting products for:", ids)
    
    do {
      let products = try await Product.products(for: ids)
      print("📦 StoreKit returned \(products.count) products.")
      
      if products.isEmpty {
        print("⚠️ StoreKit returned EMPTY product list!")
        print("   → Check product IDs EXACTLY match App Store Connect")
        print("   → Check sandbox account logged in")
        print("   → Check physical device, not simulator")
      }
      
      monthly = nil
      yearly = nil
      
      for p in products {
        print("   • StoreKit product:", p.id)
        switch p.id {
        case IAP.monthlyID:
          print("     ✅ Matched monthly product")
          monthly = p
        case IAP.yearlyID:
          print("     ✅ Matched yearly product")
          yearly = p
        default:
          print("     ⚠️ Unrecognized product:", p.id)
        }
      }
      
      if monthly == nil { print("⚠️ monthly is STILL nil!") }
      if yearly  == nil { print("⚠️ yearly is STILL nil!") }
      
    } catch {
      errorMessage = "Failed to load products: \(error)"
      print("❌ Product load error:", error)
    }
  }
  
  // MARK: - Purchase
  func buy(_ product: Product) async {
    print("\n🧾 IAPStore.buy(\(product.id))")
    
    isLoading = true
    defer { isLoading = false }
    
    do {
      let result = try await product.purchase()
      print("🛒 Purchase result:", result)
      
      switch result {
      case .success(let verification):
        if case .verified(let transaction) = verification {
          print("   ✅ PURCHASE VERIFIED for:", transaction.productID)
          await transaction.finish()
          await entitlements.refresh(reason: "after purchase")
        } else {
          print("   ⚠️ Purchase UNVERIFIED!")
        }
        
      case .userCancelled:
        print("   🚫 Purchase cancelled by user")
        
      case .pending:
        print("   ⏳ Purchase pending")
        
      @unknown default:
        print("   ❓ UNKNOWN purchase result")
      }
      
    } catch {
      errorMessage = "Purchase failed: \(error)"
      print("❌ Purchase failed:", error)
    }
  }
  
  // MARK: - Restore
  func restore() async {
    print("\n🔁 IAPStore.restore() – calling AppStore.sync()")
    
    isLoading = true
    defer { isLoading = false }
    
    do {
      try await AppStore.sync()
      print("   ✅ AppStore.sync() succeeded")
      await entitlements.refresh(reason: "restore")
    } catch {
      errorMessage = "Restore failed: \(error)"
      print("❌ Restore failed:", error)
    }
  }
}

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
  
  var priceDouble: Double {
    NSDecimalNumber(decimal: price).doubleValue
  }
}
