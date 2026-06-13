import SwiftUI
import StoreKit
import Security

enum IAP {
  // Make sure these EXACTLY match App Store Connect
  static let monthlyID = "com.kuzostudiosph.TodayI.premium.monthly"
  static let yearlyID  = "com.kuzostudiosph.TodayI.premium.yearly"
}

struct Entitlement: Codable, Equatable {
  let productId: String
  let expiresAt: Date?   // nil for lifetime/non-consumable (or unknown)
}

@MainActor
final class EntitlementStore: ObservableObject {
  @Published private(set) var active: [Entitlement] = []
  @Published var isPremium: Bool = true
  
  private let cacheService = "entitlements.v1"
  private let cacheAccount = "current"
  
  private var updatesTask: Task<Void, Never>?
  
  // MARK: - Init
  
  init() {
    print("EntitlementStore.init()")
    
    if let cached = try? loadFromKeychainOptional() {
      print("Loaded cached entitlements from Keychain: \(cached.map { $0.productId })")
      self.active = cached
    } else {
      print("No cached entitlements found in Keychain")
    }
    
    // Derive isPremium from cached immediately
    //self.isPremium = self.active.contains { $0.productId == IAP.monthlyID || $0.productId == IAP.yearlyID }
    
    // Bootstrap current status on launch.
    // Wrapped in a timeout so a stuck StoreKit call on beta OSes
    // never permanently holds the MainActor (which blocks SwiftUI rendering).
    Task {
      await withTimeout(seconds: 8) {
        await self.refresh(reason: "init()")
      }
    }
  }
  
  deinit {
    updatesTask?.cancel()
  }
  
  // MARK: - StoreKit updates
  
  /// Call once during app startup (e.g., in App.init()).
  func observeUpdates() {
    guard updatesTask == nil else {
      print("EntitlementStore.observeUpdates(): already observing")
      return
    }
    
    print("EntitlementStore.observeUpdates(): starting Transaction.updates stream")
    
    updatesTask = Task { [weak self] in
      guard let self else { return }
      
      for await update in StoreKit.Transaction.updates {
        guard !Task.isCancelled else { break }
        
        switch update {
        case .verified(let t):
          print("StoreKit update: verified transaction \(t.productID) (type: \(t.productType.rawValue))")
          // Recommended: finish once you've processed entitlement delivery.
          await t.finish()
          
        case .unverified(let t, let error):
          print("StoreKit update: UNVERIFIED transaction \(t.productID), error: \(String(describing: error))")
        }
        
        await self.refresh(reason: "Transaction.updates")
      }
    }
  }
  
  // MARK: - Refresh
  
  /// Re-scan StoreKit current entitlements and cache result.
  func refresh(reason: String = "manual") async {
    print("EntitlementStore.refresh(reason: \(reason)) at \(Date())")
    
    var result: [Entitlement] = []
    var countScanned = 0
    
    do {
      for await ent in StoreKit.Transaction.currentEntitlements {
        countScanned += 1
        
        switch ent {
        case .unverified(let t, let error):
          print("currentEntitlements: UNVERIFIED \(t.productID). error: \(String(describing: error))")
          continue
          
        case .verified(let t):
          let pid = t.productID
          let type = t.productType
          let exp  = t.expirationDate
          let rev  = t.revocationDate
          
          print("""
          currentEntitlement:
            productID: \(pid)
            type: \(type.rawValue)
            expiration: \(String(describing: exp))
            revokedAt: \(String(describing: rev))
          """)
          
          // Ignore revoked
          guard rev == nil else {
            print("Skipping \(pid) because it is revoked")
            continue
          }
          
          // IMPORTANT: Transaction.currentEntitlements already represents what Apple considers currently entitled.
          // So we generally trust it and treat it as active.
          
          switch type {
          case .autoRenewable:
            // Keep expiration if provided (useful for UI/debug), but do not gate entitlement on exp > now.
            result.append(Entitlement(productId: pid, expiresAt: exp))
            
          case .nonConsumable:
            result.append(Entitlement(productId: pid, expiresAt: nil))
            
          case .nonRenewable:
            // Non-renewables should have an expiration. Be defensive:
            if let exp, exp > Date() {
              result.append(Entitlement(productId: pid, expiresAt: exp))
            } else {
              // If exp is missing or already expired, do NOT treat it as lifetime.
              print("Non-renewable \(pid) missing/expired expiration; not adding as active")
            }
            
          default:
            print("Ignoring product type \(type.rawValue) for \(pid)")
          }
        }
      }
      
      print("Scanned \(countScanned) currentEntitlements; built \(result.count) active entitlements")
      
      // Normalize ordering for stable equality
      result.sort { $0.productId < $1.productId }
      
      // Update active + cache only if changed
      if result != active {
        print("Active entitlements changed. Old: \(active.map { $0.productId }), New: \(result.map { $0.productId })")
        active = result
        do {
          try cacheToKeychain(result)
          print("Cached entitlements to Keychain")
        } catch {
          print("Failed to cache entitlements to Keychain: \(error)")
        }
      } else {
        print("Active entitlements unchanged")
      }
      
      // Always recompute premium from the latest scan result (not from prior cached state).
      let newPremium = active.contains { $0.productId == IAP.monthlyID || $0.productId == IAP.yearlyID }
      if newPremium != isPremium {
        print("isPremium changed: \(isPremium) -> \(newPremium)")
        //isPremium = newPremium
      } else {
        print("isPremium stays: \(isPremium)")
      }
      
    } catch {
      print("Error while iterating currentEntitlements: \(error)")
    }
  }
  
  // MARK: - Keychain cache
  
  private func cacheToKeychain(_ ents: [Entitlement]) throws {
    let data = try JSONEncoder().encode(ents)
    print("Encoding entitlements for Keychain: \(ents.map { $0.productId })")
    try Keychain.save(service: cacheService, account: cacheAccount, data: data)
  }
  
  /// Returns nil if there is no cache entry.
  private func loadFromKeychainOptional() throws -> [Entitlement]? {
    print("Trying to load entitlements from Keychain (service: \(cacheService), account: \(cacheAccount))")
    
    guard let data = try Keychain.load(service: cacheService, account: cacheAccount) else {
      print("No data found in Keychain")
      return nil
    }
    
    let decoded = try JSONDecoder().decode([Entitlement].self, from: data)
    print("Decoded entitlements from Keychain: \(decoded.map { $0.productId })")
    return decoded
  }
}
