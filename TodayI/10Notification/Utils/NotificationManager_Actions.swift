//
//  NotificationManager_Actions.swift
//  TodayI
//

import Foundation
import UserNotifications
import FirebaseAuth
import SwiftData

/// Mood buttons attached to the daily "How was your day?" nudge, so answering costs
/// one tap from the Lock Screen instead of a launch, a tab and a form.
///
/// iOS only shows about four actions, so this is three moods plus an escape hatch
/// into the app — not all seven. The three are the ones a quick check-in most often
/// lands on; anything more considered deserves the full Create screen anyway.
extension NotificationManager {

  enum DailyCheckIn {
    static let category = "DAILY_CHECKIN"
    static let moodActionPrefix = "LOG_MOOD_"
    static let openAction = "OPEN_CREATE"

    /// Kept short: these are button labels, not sentences.
    static let quickMoods: [Mood] = [.happy, .neutral, .sad]
  }

  /// Registers the category. Safe to call more than once — it replaces wholesale.
  func registerNotificationCategories() {
    let moodActions = DailyCheckIn.quickMoods.map { mood in
      UNNotificationAction(
        identifier: DailyCheckIn.moodActionPrefix + mood.rawValue,
        title: mood.rawValue,
        // No `.foreground`: logging a mood shouldn't yank you into the app. iOS
        // wakes us in the background, we write, and the user stays where they were.
        options: []
      )
    }

    let openAction = UNNotificationAction(
      identifier: DailyCheckIn.openAction,
      title: "Something else…",
      options: [.foreground]
    )

    let category = UNNotificationCategory(
      identifier: DailyCheckIn.category,
      actions: moodActions + [openAction],
      intentIdentifiers: [],
      options: []
    )

    UNUserNotificationCenter.current().setNotificationCategories([category])
    print("🔔 Registered notification category:", DailyCheckIn.category)
  }

  /// Handles a tapped action. Returns true if it consumed the response.
  @MainActor
  @discardableResult
  func handleNotificationResponse(_ response: UNNotificationResponse) async -> Bool {
    let id = response.actionIdentifier
    guard id.hasPrefix(DailyCheckIn.moodActionPrefix),
          let mood = Mood(rawValue: String(id.dropFirst(DailyCheckIn.moodActionPrefix.count)))
    else { return false }

    await logMoodFromNotification(mood)
    return true
  }

  /// Writes a mood-only memory for today, private by default.
  ///
  /// Private because a one-tap answer is not an informed choice to publish. Mood-only
  /// because the point is that the cheapest honest answer still counts — that is what
  /// keeps a streak from pushing people into writing filler.
  @MainActor
  private func logMoodFromNotification(_ mood: Mood) async {
    // Straight from FirebaseAuth rather than AuthStore: on a background launch the
    // SwiftUI scene never builds, so no AuthStore exists — but the signed-in session
    // is persisted and available as soon as Firebase is configured.
    guard let manager = AppServices.shared.swiftDataManager,
          let uid = Auth.auth().currentUser?.uid
    else {
      print("⚠️ Mood action arrived before the app was ready to write")
      return
    }

    // Username and photo come from the locally cached profile; the notification path
    // must not depend on a network round trip.
    let profile = manager.localUser(id: uid)

    // Don't quietly add a second entry: on the free tier it would be hidden behind
    // the paywall, and either way the user asked for one answer, not two.
    if manager.hasMemoryToday(userID: uid) {
      print("🔔 Mood action ignored — today already has a memory")
      return
    }

    let payload = PostPayload(
      mood: mood,
      isPublic: false,
      isPremium: AppServices.shared.entitlements?.isPremium ?? false,
      text: "",
      images: [],
      videoURL: nil,
      audioURL: nil,
      linkString: nil
    )

    do {
      _ = try manager.savePostPayload(
        payload,
        userID: uid,
        username: profile?.username ?? "Me",
        remoteProfilePhotoURL: profile?.photoURL
      )
      print("✅ Logged \(mood.rawValue) from notification")
      // Home may already be on screen; without this it keeps insisting today is empty.
      NotificationCenter.default.post(name: .memoryDidChangeLocally, object: nil)
    } catch {
      print("❌ Failed to log mood from notification:", error)
    }
  }
}
