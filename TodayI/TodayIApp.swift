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
  
    // Ensure Application Support directory exists
    do {
      let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      if let appSupportURL = urls.first {
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
      }
    } catch {
      print("Failed to ensure Application Support directory:", error)
    }
    
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
          store.observeUpdates()   // existing
          
          // 🔥 1. Try activating a trial if this is first launch
          let activated = await FirebaseFirestoreManager.activateDeviceTrialIfNeeded()
          print("Trial activation result: \(activated)")
          
          // 🔍 2. Check if trial is still valid
//          let isTrialPremium = await FirebaseFirestoreManager.checkDeviceTrialPremium()
//          print("Trial active? \(isTrialPremium)")
//          
//          // 🎁 3. Merge boot trial into premium status
//          // If user SUBSCRIBED, entitlements.isPremium = true already overrides this
//          if isTrialPremium && store.isPremium == false {
//            store.isPremium = true
//            print("🎉 Trial premium unlocked!")
//          }
        }
        .onAppear {
          Task {
            await NotificationManager.shared.configure()
          }
        }
    }
    .modelContainer(container)
  }
}
