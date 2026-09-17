//
//  StartupDiagnostics.swift
//  TodayI
//

import Foundation
import FirebaseCrashlytics

/// Buffers failures that happen *before* Firebase is available, then reports them as
/// Crashlytics non-fatals once it is.
///
/// `TodayIApp.init()` builds the `ModelContainer` before `AppDelegate`
/// `didFinishLaunching` calls `FirebaseApp.configure()`, so recording straight from
/// that catch block would touch an unconfigured default app. Buffer there, flush here.
///
/// The case this exists for: when the container fails to open, the app quietly falls
/// back to an in-memory store and everything the user writes that session is lost at
/// the next launch. Without a non-fatal there is nothing in the console to tell us it
/// is happening to real users.
@MainActor
enum StartupDiagnostics {

  enum Domain: String {
    case modelContainerLoadFailed
  }

  private struct Pending {
    let domain: Domain
    let error: Error
  }

  private static var pending: [Pending] = []
  private static var didFlush = false

  /// Safe to call before `FirebaseApp.configure()`.
  static func record(_ error: Error, domain: Domain) {
    pending.append(Pending(domain: domain, error: error))
    print("📮 Buffered startup non-fatal (\(domain.rawValue)): \(error)")
  }

  /// Call once, immediately after `FirebaseApp.configure()`.
  static func flush() {
    guard !didFlush else { return }
    didFlush = true
    guard !pending.isEmpty else { return }

    let crashlytics = Crashlytics.crashlytics()
    for item in pending {
      crashlytics.record(
        error: item.error,
        userInfo: [
          "domain": item.domain.rawValue,
          "detail": String(describing: item.error)
        ]
      )
      print("📤 Reported startup non-fatal to Crashlytics: \(item.domain.rawValue)")
    }
    pending.removeAll()
  }
}
