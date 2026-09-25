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
  
  func unsubscribePreviousUserTopicIfNeeded() {
    let key = "lastUserTopicUid"
    // Holds the full topic ("user_<uid>"), written only after a subscribe succeeds.
    guard let topic = UserDefaults.standard.string(forKey: key) else { return }
    enqueueUnsubscribe(topic: topic) {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}
