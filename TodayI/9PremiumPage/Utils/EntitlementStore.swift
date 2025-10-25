import SwiftUI
import StoreKit
import Security

enum IAP {
  static let monthlyID = "com.kuzostudiosph.todayi.premium.monthly"
  static let yearlyID  = "com.kuzostudiosph.todayi.premium.yearly"
}

struct Entitlement: Codable, Equatable {
  let productId: String
  let expiresAt: Date?   // nil for lifetime/non-consumable
}

@MainActor
final class EntitlementStore: ObservableObject {
  @Published private(set) var active: [Entitlement] = []
  @Published var isPremium: Bool = false   // ← keep this, we’ll set it in refresh()
  
  private let cacheService = "entitlements.v1"
  private let cacheAccount = "current"
  
  init() {
    if let cached = try? loadFromKeychain() {
      self.active = cached
    }
    // Bootstrap current status on launch
    Task { await refresh() }
  }
  
  /// Call once during app startup (e.g., in App.init())
  func observeUpdates() {
    Task.detached { [weak self] in
      // Fully-qualify StoreKit.Transaction to avoid name collisions
      for await _ in StoreKit.Transaction.updates {
        await self?.refresh()
      }
    }
  }
  
  /// Re-scan StoreKit current entitlements and cache result.
  func refresh() async {
    var result: [Entitlement] = []
    
    for await ent in StoreKit.Transaction.currentEntitlements {
      guard case .verified(let t) = ent else { continue }
      guard t.revocationDate == nil else { continue }
      
      switch t.productType {
      case .autoRenewable:
        guard let exp = t.expirationDate, exp > Date() else { continue }
        result.append(Entitlement(productId: t.productID, expiresAt: exp))
        
      case .nonConsumable:
        result.append(Entitlement(productId: t.productID, expiresAt: nil))
        
      case .nonRenewable:
        if let exp = t.expirationDate, exp > Date() {
          result.append(Entitlement(productId: t.productID, expiresAt: exp))
        } else {
          result.append(Entitlement(productId: t.productID, expiresAt: nil))
        }
        
      default:
        break
      }
    }
    
    result.sort { $0.productId < $1.productId }
    
    if result != active {
      active = result
      try? cacheToKeychain(result)
    }
    
    // 🔑 Decide premium: any active sub of our group
    isPremium = active.contains { $0.productId == IAP.monthlyID || $0.productId == IAP.yearlyID }
  }
  
  // MARK: - Keychain cache (as you had)
  private func cacheToKeychain(_ ents: [Entitlement]) throws {
    let data = try JSONEncoder().encode(ents)
    try Keychain.save(service: cacheService, account: cacheAccount, data: data)
  }
  
  private func loadFromKeychain() throws -> [Entitlement] {
    guard let data = try Keychain.load(service: cacheService, account: cacheAccount) else {
      return []
    }
    return try JSONDecoder().decode([Entitlement].self, from: data)
  }
}
