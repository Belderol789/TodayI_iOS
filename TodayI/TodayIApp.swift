import SwiftUI
import FirebaseCore
import SwiftData
import AVFAudio
import StoreKit
import FirebaseMessaging
import UserNotifications
import UIKit

@main
struct TodayIApp: App {
  @StateObject private var store: EntitlementStore
  @StateObject private var authStore: AuthStore
  @StateObject private var iapStore: IAPStore
  private let container: ModelContainer
  private let manager: SwiftDataManager
  
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  
  init() {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
    try? AVAudioSession.sharedInstance().setActive(true)
    // Create one shared container
    container = try! ModelContainer(
      for: UserModel.self,
      MemoryModel.self,
      DateModel.self,
      BlockedUserList.self      // ← add this
    )
    
    // Create AuthStore & SwiftDataManager using same context
    let context = container.mainContext
    let entitlements = EntitlementStore()
    _store = StateObject(wrappedValue: entitlements)
    _authStore = StateObject(wrappedValue: AuthStore(context: context))
    _iapStore = StateObject(wrappedValue: IAPStore(entitlements: entitlements))
    manager = SwiftDataManager(context: context, store: entitlements)
  }
  
  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .environmentObject(authStore)
        .environmentObject(iapStore)
        .environment(\.swiftDataManager, manager)
        .task {
          await store.refresh()
          store.observeUpdates()
        }
        .onAppear {
          Task {
            await NotificationManager.shared.configure() // requests auth + UIApplication.shared.registerForRemoteNotifications()
          }
          store.observeUpdates()
        }
    }
    .modelContainer(container) // Use the same container
  }
}

/*
 
 // Call this once on launch (e.g., .task in your RootView)
 func debugIAP() {
 Task {
 print("Bundle ID:", Bundle.main.bundleIdentifier ?? "nil")
 print("Product IDs:", IAP.monthlyID, IAP.yearlyID)
 
 do {
 let products = try await Product.products(for: [IAP.monthlyID, IAP.yearlyID])
 print("Loaded products count:", products.count)
 for p in products {
 print("•", p.id, p.displayName, p.price.formatted(.currency(code: p.priceFormatStyle.currencyCode)))
 if let sp = p.subscription?.subscriptionPeriod {
 print("  period:", sp.unit, sp.value)
 }
 }
 } catch {
 print("❌ Product load failed:", error)
 }
 
 // Check StoreKit entitlement stream reachable
 var sawEntitlement = false
 for await ent in StoreKit.Transaction.currentEntitlements {
 sawEntitlement = true
 print("Entitlement result:", ent)
 break
 }
 if !sawEntitlement {
 print("⚠️ No entitlement stream results (might be fine if none purchased yet).")
 }
 }
 }
 
 */
