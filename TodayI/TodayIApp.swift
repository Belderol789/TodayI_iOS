//
//  TodayIApp.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/3/25.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }
}

@main
struct TodayIApp: App {
  
  @StateObject private var store = EntitlementStore()
  
  var body: some Scene {
    WindowGroup {
      CalendarView()
        .environmentObject(store)
        .task {
          await store.refresh()     // verify with StoreKit at launch
          store.observeUpdates()    // keep in sync with changes
        }
    }
    .modelContainer(for: DateModel.self)
  }
}
