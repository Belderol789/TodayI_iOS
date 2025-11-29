import SwiftUI
import StoreKit
import Security

enum IAP {
  // ⚠️ Make sure these EXACTLY match App Store Connect
  static let monthlyID = "com.kuzostudiosph.TodayI.premium.monthly"
  static let yearlyID  = "com.kuzostudiosph.TodayI.premium.yearly"
}

struct Entitlement: Codable, Equatable {
  let productId: String
  let expiresAt: Date?   // nil for lifetime/non-consumable
}

@MainActor
final class EntitlementStore: ObservableObject {
  @Published private(set) var active: [Entitlement] = []
  @Published var isPremium: Bool = false
  
  private let cacheService = "entitlements.v1"
  private let cacheAccount = "current"
  
  // MARK: - Init
  
  init() {
    print("🧩 EntitlementStore.init()")
    
    if let cached = try? loadFromKeychain() {
      print("🔑 Loaded cached entitlements from Keychain: \(cached.map { $0.productId })")
      self.active = cached
    } else {
      print("🔑 No cached entitlements found in Keychain")
    }
    
    // Bootstrap current status on launch
    Task {
      await self.refresh(reason: "init()")
    }
  }
  
  // MARK: - StoreKit updates
  
  /// Call once during app startup (e.g., in App.init())
  func observeUpdates() {
    print("👂 EntitlementStore.observeUpdates() – starting StoreKit.Transaction.updates stream")
    
    Task.detached { [weak self] in
      for await update in StoreKit.Transaction.updates {
        guard let self else { continue }
        switch update {
        case .verified(let t):
          print("📬 StoreKit update: verified transaction for product \(t.productID) (type: \(t.productType.rawValue))")
        case .unverified(let t, let error):
          print("⚠️ StoreKit update: UNVERIFIED transaction \(t.productID), error: \(String(describing: error))")
        }
        await self.refresh(reason: "StoreKit.Transaction.updates")
      }
    }
  }
  
  // MARK: - Refresh
  
  /// Re-scan StoreKit current entitlements and cache result.
  func refresh(reason: String = "manual") async {
    print("🔄 EntitlementStore.refresh(reason: \(reason)) at \(Date())")
    
    var result: [Entitlement] = []
    
    do {
      var countScanned = 0
      
      for await ent in StoreKit.Transaction.currentEntitlements {
        countScanned += 1
        
        switch ent {
        case .unverified(let t, let error):
          print("⚠️ currentEntitlements: UNVERIFIED transaction for product \(t.productID). error: \(String(describing: error))")
          continue
          
        case .verified(let t):
          let pid = t.productID
          let type = t.productType
          let exp  = t.expirationDate
          let rev  = t.revocationDate
          
          print("""
          🔍 currentEntitlement:
            • productID: \(pid)
            • type: \(type.rawValue)
            • expiration: \(String(describing: exp))
            • revokedAt: \(String(describing: rev))
          """)
          
          // Ignore revoked
          guard rev == nil else {
            print("   ↪︎ Skipping \(pid) because it is revoked")
            continue
          }
          
          switch type {
          case .autoRenewable:
            if let exp = exp, exp > Date() {
              print("   ✅ Active auto-renewable subscription: \(pid) (expires at \(exp))")
              result.append(Entitlement(productId: pid, expiresAt: exp))
            } else {
              print("   🚫 Auto-renewable \(pid) has expired or missing expiration")
            }
            
          case .nonConsumable:
            print("   ✅ Non-consumable entitlement: \(pid)")
            result.append(Entitlement(productId: pid, expiresAt: nil))
            
          case .nonRenewable:
            if let exp = exp, exp > Date() {
              print("   ✅ Active non-renewable: \(pid) (expires at \(exp))")
              result.append(Entitlement(productId: pid, expiresAt: exp))
            } else {
              print("   ✅ Non-renewable (no expiration or already expired): \(pid)")
              result.append(Entitlement(productId: pid, expiresAt: nil))
            }
            
          default:
            print("   ℹ️ Ignoring product type \(type.rawValue) for \(pid)")
          }
        }
      }
      
      print("📊 Scanned \(countScanned) currentEntitlements; built \(result.count) active entitlements")
      
      // Normalize ordering for stable equality
      result.sort { $0.productId < $1.productId }
      
      if result != active {
        print("💾 Active entitlements changed. Old: \(active.map { $0.productId }), New: \(result.map { $0.productId })")
        active = result
        do {
          try cacheToKeychain(result)
          print("🔐 Cached entitlements to Keychain")
        } catch {
          print("⚠️ Failed to cache entitlements to Keychain:", error)
        }
      } else {
        print("ℹ️ Active entitlements unchanged")
      }
      
      // Decide premium: any active sub of our group
      let oldPremium = isPremium
      isPremium = active.contains { $0.productId == IAP.monthlyID || $0.productId == IAP.yearlyID }
      
      if isPremium != oldPremium {
        print("🏅 isPremium changed: \(oldPremium) → \(isPremium)")
      } else {
        print("ℹ️ isPremium stays:", isPremium)
      }
      
    } catch {
      print("❌ Error while iterating currentEntitlements:", error)
    }
  }
  
  // MARK: - Keychain cache
  
  private func cacheToKeychain(_ ents: [Entitlement]) throws {
    let data = try JSONEncoder().encode(ents)
    print("🧾 Encoding entitlements for Keychain:", ents.map { $0.productId })
    try Keychain.save(service: cacheService, account: cacheAccount, data: data)
  }
  
  private func loadFromKeychain() throws -> [Entitlement] {
    print("🔎 Trying to load entitlements from Keychain (service: \(cacheService), account: \(cacheAccount))")
    guard let data = try Keychain.load(service: cacheService, account: cacheAccount) else {
      print("   ↪︎ No data found in Keychain")
      return []
    }
    let decoded = try JSONDecoder().decode([Entitlement].self, from: data)
    print("   ↪︎ Decoded entitlements from Keychain:", decoded.map { $0.productId })
    return decoded
  }
}
