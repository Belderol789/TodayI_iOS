//
//  NotificationManager_FirebaseMessaging.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 11/2/25.
//

import FirebaseMessaging

extension NotificationManager {
  /// Subscribes to the per-user topic that carries like and comment milestones.
  /// Goes through the APNs-aware queue — firing this straight at Messaging on a cold
  /// launch is what silently dropped it, since the FCM token usually lands first.
  func subscribeUserTopic(uid: String) {
    enqueueSubscribe(topic: "user_\(uid)", persistKey: "lastUserTopicUid")
  }
  
  /// Keeps this device's `admin_reports` subscription in step with whoever is signed in.
  ///
  /// FCM topics belong to the *device*, not the account. Subscribing only when an admin
  /// profile loaded meant the subscription outlived the admin: sign out, and the next
  /// person on this phone — a guest, or someone else's account — kept receiving every
  /// moderation alert, with other users' IDs in it. Called on every profile load, so a
  /// non-admin session always unsubscribes. Both directions go through the APNs-safe
  /// queue, like every other topic.
  func syncAdminReportsTopic(isAdmin: Bool) {
    let key = "adminReportsTopic"
    if isAdmin {
      enqueueSubscribe(topic: "admin_reports", persistKey: key)
    } else if UserDefaults.standard.string(forKey: key) != nil {
      enqueueUnsubscribe(topic: "admin_reports") {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }
  }

  func unsubscribePreviousUserTopicIfNeeded() {
    let key = "lastUserTopicUid"
    // Holds the full topic ("user_<uid>"), written only after a subscribe succeeds.
    guard let topic = UserDefaults.standard.string(forKey: key) else { return }
    enqueueUnsubscribe(topic: topic) {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}
