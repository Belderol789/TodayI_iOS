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
  @StateObject private var auth = AuthStore()
  
  var body: some Scene {
    WindowGroup {
      CalendarView()
        .environmentObject(store)
        .environmentObject(auth)
        .task {
          await store.refresh()
          store.observeUpdates()
        }
    }
    .modelContainer(for: [DateModel.self, MemoryModel.self])   // ← include both models
  }
}
