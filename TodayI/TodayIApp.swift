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

    // Audio session configured lazily on a background thread to avoid blocking first render
    Task.detached(priority: .utility) {
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
      try? AVAudioSession.sharedInstance().setActive(true)
    }

    // Create one shared container — with a fallback chain so a schema
    // migration failure on iOS betas doesn't silently crash the app.
    let schema = Schema([UserModel.self, MemoryModel.self, DateModel.self, BlockedUserList.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

    if let c = try? ModelContainer(for: schema, configurations: config) {
      container = c
    } else {
      print("⚠️ ModelContainer init failed; deleting store and retrying.")
      let storeURL = config.url
      try? FileManager.default.removeItem(at: storeURL)
      let shmURL = storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
      let walURL = storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
      try? FileManager.default.removeItem(at: shmURL)
      try? FileManager.default.removeItem(at: walURL)
      if let c = try? ModelContainer(for: schema, configurations: config) {
        container = c
      } else {
        print("❌ ModelContainer retry failed; falling back to in-memory store.")
        container = try! ModelContainer(for: schema,
          configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
      }
    }

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
          store.observeUpdates()

          let activated = await FirebaseFirestoreManager.activateDeviceTrialIfNeeded()
          print("Trial activation result: \(activated)")
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
