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

    // Build the container using versioned schema + migration plan.
    // New optional columns are handled automatically (lightweight migration).
    // For breaking changes: add AppSchemaV2 + a MigrationStage in AppSchema.swift.
    do {
      container = try ModelContainer(
        for: Schema(versionedSchema: AppSchemaV1.self),
        migrationPlan: AppMigrationPlan.self,
        configurations: [ModelConfiguration(isStoredInMemoryOnly: false)]
      )
    } catch {
      // Migration failed — fall back to in-memory so the app still opens.
      // User data is NOT deleted; the on-disk store is left intact for recovery.
      //
      // This fallback is silent to the user but destructive in effect: nothing written
      // this session survives the next launch. Report it so we find out when real users
      // hit it. Firebase isn't configured yet here, so it's buffered until it is.
      print("❌ ModelContainer failed (\(error)); running in-memory for this session.")
      MainActor.assumeIsolated {
        StartupDiagnostics.record(error, domain: .modelContainerLoadFailed)
      }
      container = try! ModelContainer(
        for: Schema(versionedSchema: AppSchemaV1.self),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
      )
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
          // Self-heals stores written by builds that stamped dayKey from `Date()`.
          let repaired = manager.repairMismatchedDayKeys()
          if repaired > 0 { print("🩹 Repaired \(repaired) mismatched dayKey(s)") }

          store.observeUpdates()

          let activated = await FirebaseFirestoreManager.activateDeviceTrialIfNeeded()
          print("Trial activation result: \(activated)")
        }
    }
    .modelContainer(container)
  }
}
