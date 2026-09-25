//
//  AppServices.swift
//  TodayI
//

import Foundation

/// A narrow bridge from `AppDelegate` to the stores `TodayIApp` owns.
///
/// Notification actions are delivered to the app delegate, which has no access to
/// the `@EnvironmentObject` graph — and a mood tapped from a notification has to be
/// written even when the app was launched into the background with no UI at all.
/// `TodayIApp.init` fills these in, and it runs before `didFinishLaunching`, so they
/// are set by the time any notification response arrives.
///
/// Only Firebase-free stores belong here. `AuthStore` builds a Firestore handle in
/// its initialiser, so it cannot exist this early — callers read the uid from
/// `Auth.auth().currentUser` instead, which also survives a background launch where
/// no scene is ever created.
///
/// Deliberately not a general-purpose service locator: add to it only when something
/// outside SwiftUI genuinely needs a store.
@MainActor
final class AppServices {
  static let shared = AppServices()
  private init() {}

  weak var swiftDataManager: SwiftDataManager?
  weak var entitlements: EntitlementStore?
}
