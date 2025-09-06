import SwiftUI
import StoreKit
import Security

struct Entitlement: Codable, Equatable {
  let productId: String
  let expiresAt: Date?   // nil for lifetime/non-consumable
}

@MainActor
final class EntitlementStore: ObservableObject {
  @Published private(set) var active: [Entitlement] = []
  
  private let cacheService = "entitlements.v1"
  private let cacheAccount = "current"
  
  init() {
    // Optimistic boot: load last known entitlements from Keychain
    if let cached = try? loadFromKeychain() {
      self.active = cached
    }
  }
  
  func observeUpdates() {
    Task.detached { [weak self] in
      for await _ in Transaction.updates {
        await self?.refresh()
      }
    }
  }
  
  /// Re-scan StoreKit current entitlements and cache result.
  func refresh() async {
    var result: [Entitlement] = []
    
    for await ent in Transaction.currentEntitlements {
      guard case .verified(let t) = ent else { continue }          // ignore unverified
      guard t.revocationDate == nil else { continue }               // refunded/revoked
      
      switch t.productType {
      case .autoRenewable:
        guard let exp = t.expirationDate, exp > Date() else { continue }
        result.append(Entitlement(productId: t.productID, expiresAt: exp))
      case .nonConsumable:
        result.append(Entitlement(productId: t.productID, expiresAt: nil))
      case .nonRenewable:
        // Treat non-renewables like subs if they carry an expirationDate
        if let exp = t.expirationDate, exp > Date() {
          result.append(Entitlement(productId: t.productID, expiresAt: exp))
        } else {
          // If you sell lifetime non-renewable, leave expiresAt nil
          result.append(Entitlement(productId: t.productID, expiresAt: nil))
        }
      default:
        break
      }
    }
    
    // Sort deterministically (optional)
    result.sort { $0.productId < $1.productId }
    
    // Publish & cache
    if result != active {
      active = result
    }
    try? cacheToKeychain(result)
  }
  
  // MARK: - Keychain cache
  
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
  
  // Convenience
  @Published var isPremium: Bool = false
//  var isPremium: Bool {
//    // Decide your app’s premium rule. Example: any active entitlement.
//    !active.isEmpty
//  }
}
