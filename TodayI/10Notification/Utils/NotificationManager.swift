import Foundation
import UserNotifications
import FirebaseMessaging
import UIKit

final class NotificationManager: NSObject {
  static let shared = NotificationManager()
  private override init() {}
  
  private var cachedFCMToken: String?
  
  // MARK: - Bootstrap
  func configure() async -> Bool {
    await withCheckedContinuation { cont in
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        if let error = error { print("Notification auth error:", error) }
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
        cont.resume(returning: granted)
      }
    }
  }
  
  // MARK: - FCM helpers
  func setFCMToken(_ token: String?) {
    cachedFCMToken = token
    // Example: subscribe to a topic when available
    if let token = token, !token.isEmpty {
      Messaging.messaging().subscribe(toTopic: "general") { error in
        if let error = error {
          print("Topic subscribe failed:", error)
        } else {
          print("Subscribed to topic 'general' with token:", token)
        }
      }
    }
    
    // ✅ NEW: subscribe to timezone topic
    subscribeToTimezoneTopicIfNeeded()
  }
  
  private func subscribeToTimezoneTopicIfNeeded() {
    let seconds = TimeZone.current.secondsFromGMT()
    let hours = seconds / 3600
    let signPrefix = hours >= 0 ? "p" : "m"
    let absH = abs(hours)
    let tz = "\(signPrefix)\(String(format: "%02d", absH))" // p08, m05, etc.
    
    // Existing daily topic
    subscribe(topic: "daily8pm_tz_\(tz)", key: "lastTZTopic_daily8pm")
    
    // ✅ NEW: world mood topic (matches your Cloud Function)
    subscribe(topic: "worldmood_6pm_tz_\(tz)", key: "lastTZTopic_worldmood6pm")
  }
  
  private func subscribe(topic: String, key: String) {
    let last = UserDefaults.standard.string(forKey: key)
    
    if last != topic {
      if let last {
        Messaging.messaging().unsubscribe(fromTopic: last) { _ in
          print("Unsubscribed from \(last)")
        }
      }
      Messaging.messaging().subscribe(toTopic: topic) { err in
        if let err = err { print("Subscribe failed:", err) }
        else {
          print("Subscribed topic:", topic)
          UserDefaults.standard.set(topic, forKey: key)
        }
      }
    }
  }
  
  func currentFCMToken() -> String? {
    return cachedFCMToken
  }
  
  // MARK: - Local: schedule daily at fixed wall clock time
  func scheduleDaily(hour: Int, minute: Int, identifier: String = "daily-8pm", title: String, body: String) async throws {
    // Ensure auth first
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
      throw NSError(domain: "NotificationManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Notifications not authorized"])
    }
    
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    
    var dateComponents = DateComponents()
    dateComponents.hour = hour
    dateComponents.minute = minute
    
    // Repeat daily at the specified time
    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
    
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    try await UNUserNotificationCenter.current().add(request)
  }
  
  // MARK: - Idempotent daily scheduling (remove then add)
  func rescheduleDaily(id: String,
                       hour: Int,
                       minute: Int,
                       title: String,
                       body: String) async throws {
    // Remove any existing with same ID first
    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(withIdentifiers: [id])
    
    try await scheduleDaily(hour: hour,
                            minute: minute,
                            identifier: id,
                            title: title,
                            body: body)
  }
  
  // MARK: - Local: schedule one-time
  func scheduleOneTime(on date: Date, id: String, title: String, body: String) async throws {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    
    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    try await UNUserNotificationCenter.current().add(request)
  }
  
  func cancelAll() {
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
  }
  
  // MARK: - Remote: background data push entry (silent)
  // Call this from AppDelegate's didReceiveRemoteNotification:fetchCompletionHandler if you enable silent pushes.
  func handleRemoteDataPush(_ userInfo: [AnyHashable: Any], completion: @escaping (UIBackgroundFetchResult) -> Void) {
    // Example: parse payload and refresh local cache
    // Do lightweight work only; Apple enforces time limits in background.
    completion(.newData)
  }
  
  // Cancel just one scheduled notification by id
  func cancel(id: String) {
    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(withIdentifiers: [id])
    UNUserNotificationCenter.current()
      .removeDeliveredNotifications(withIdentifiers: [id])
  }
  
  // Update time only, keeping same title/body
  func updateDailyTime(id: String, newHour: Int, newMinute: Int,
                       title: String, body: String) async {
    do {
      try await rescheduleDaily(id: id,
                                hour: newHour,
                                minute: newMinute,
                                title: title,
                                body: body)
    } catch {
      print("updateDailyTime failed:", error)
    }
  }
  
  // Debug: print pending requests
  func dumpPending() {
    UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
      for r in reqs {
        print("PENDING \(r.identifier): \(String(describing: r.trigger))")
      }
    }
  }
}
