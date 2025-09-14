import SwiftUI
import FirebaseCore
import SwiftData

@main
struct TodayIApp: App {
  @StateObject private var store = EntitlementStore()
  @StateObject private var authStore: AuthStore
  private let container: ModelContainer
  private let manager: SwiftDataManager
  
  init() {
    FirebaseApp.configure()
    
    // Create one shared container
    container = try! ModelContainer(for: UserModel.self, MemoryModel.self, DateModel.self)
    
    // Create AuthStore & SwiftDataManager using same context
    let context = container.mainContext
    let entitlements = EntitlementStore()
    _authStore = StateObject(wrappedValue: AuthStore(context: context))
    manager = SwiftDataManager(context: context, store: entitlements)
  }
  
  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .environmentObject(authStore)
        .environment(\.swiftDataManager, manager)
        .task {
          await store.refresh()
          store.observeUpdates()
        }
    }
    .modelContainer(container) // Use the same container
  }
}
