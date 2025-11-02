//
//  NotificationManager_FirebaseMessaging.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 11/2/25.
//

import FirebaseMessaging

extension NotificationManager {
  func subscribeUserTopic(uid: String) {
    let topic = "user_\(uid)"
    Messaging.messaging().subscribe(toTopic: topic) { err in
      if let err = err { print("user topic subscribe failed:", err) }
      else { print("Subscribed to", topic) }
    }
    UserDefaults.standard.set(uid, forKey: "lastUserTopicUid")
  }
  
  func unsubscribePreviousUserTopicIfNeeded() {
    let key = "lastUserTopicUid"
    guard let old = UserDefaults.standard.string(forKey: key) else { return }
    let topic = "user_\(old)"
    Messaging.messaging().unsubscribe(fromTopic: topic) { err in
      if let err = err { print("user topic unsubscribe failed:", err) }
      else { print("Unsubscribed from", topic) }
    }
    UserDefaults.standard.removeObject(forKey: key)
  }
}
