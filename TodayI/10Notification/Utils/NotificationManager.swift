import Foundation
import UserNotifications
import FirebaseMessaging
import UIKit

final class NotificationManager: NSObject {
  static let shared = NotificationManager()
  private override init() {}
  
  private var cachedFCMToken: String?
  
  // MARK: - Bootstrap

  /// Registers with APNs when permission was granted in an earlier session, without
  /// prompting.
  ///
  /// `configure()` was the only caller of `registerForRemoteNotifications()`, and it
  /// only runs from the first-post prompt — so on every later launch no APNs token
  /// ever arrived, the topic queue never flushed, and push silently stopped working
  /// for users who had already said yes. Call this on every launch instead.
  func registerForRemoteNotificationsIfAuthorized() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    default:
      // Not determined or denied: registering here would be wrong (or a no-op).
      // `configure()` handles asking, when the app has earned the right to.
      break
    }
  }

  func configure() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let current = await center.notificationSettings()

    switch current.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
      return true
    case .notDetermined:
      return await withCheckedContinuation { cont in
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
          if let error = error { print("Notification auth error:", error) }
          DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
          cont.resume(returning: granted)
        }
      }
    case .denied:
      return false
    @unknown default:
      return false
    }
  }
  
  // MARK: - Topic subscription gating
  //
  // FCM refuses `subscribe(toTopic:)` until an APNS token has been handed to
  // Messaging, failing with code 505 ("No APNS token specified before fetching FCM
  // Token"). On a cold launch the FCM *registration* token normally arrives first,
  // so every subscribe fired at that moment was lost — including `user_{uid}`, which
  // is the only way like and comment milestones reach the device, and the per-offset
  // timezone topics behind the 8PM and 6PM nudges. Nothing retried them.
  //
  // So every subscribe now goes through this queue: run it if APNS is ready, park it
  // if not, and flush when `apnsTokenDidRegister()` fires from the app delegate. If
  // the user denies notifications APNS never registers and the queue simply never
  // drains, which is correct — there is no push to receive.

  private enum TopicOp: String { case subscribe, unsubscribe }

  private struct PendingTopic {
    let op: TopicOp
    let topic: String
    /// Runs only if the server accepts. Persisting eagerly made a failed call look
    /// done, which left the unsubscribe path aiming at a topic we were never on.
    let onSuccess: (() -> Void)?
  }

  private var isAPNSTokenReady = false
  private var pendingTopics: [PendingTopic] = []

  /// Call from `didRegisterForRemoteNotificationsWithDeviceToken`, after handing the
  /// token to `Messaging`.
  func apnsTokenDidRegister() {
    isAPNSTokenReady = true
    guard !pendingTopics.isEmpty else { return }
    let queued = pendingTopics
    pendingTopics.removeAll()
    print("📡 APNs ready — flushing \(queued.count) queued topic operation(s)")
    queued.forEach(perform)
  }

  /// Subscribes now, or as soon as APNs is available.
  func enqueueSubscribe(topic: String, persistKey: String? = nil) {
    enqueue(PendingTopic(op: .subscribe, topic: topic, onSuccess: persistKey.map { key in
      { UserDefaults.standard.set(topic, forKey: key) }
    }))
  }

  /// Unsubscribes now, or as soon as APNs is available. **Unsubscribe needs the APNs
  /// token just as much as subscribe does** — calling Messaging directly fails with
  /// the same 505 and, because nothing retries, silently leaves the device on a topic.
  func enqueueUnsubscribe(topic: String, onSuccess: (() -> Void)? = nil) {
    enqueue(PendingTopic(op: .unsubscribe, topic: topic, onSuccess: onSuccess))
  }

  private func enqueue(_ pending: PendingTopic) {
    guard isAPNSTokenReady else {
      // A later op on the same topic supersedes an earlier one, so a queued
      // subscribe followed by an unsubscribe doesn't run both.
      pendingTopics.removeAll { $0.topic == pending.topic }
      pendingTopics.append(pending)
      print("⏳ Queued \(pending.op.rawValue) until APNs is ready:", pending.topic)
      return
    }
    perform(pending)
  }

  private func perform(_ pending: PendingTopic) {
    let handler: (Error?) -> Void = { error in
      if let error {
        print("❌ Topic \(pending.op.rawValue) failed (\(pending.topic)):", error)
        return
      }
      print("✅ \(pending.op.rawValue.capitalized)d topic:", pending.topic)
      pending.onSuccess?()
    }

    switch pending.op {
    case .subscribe:   Messaging.messaging().subscribe(toTopic: pending.topic, completion: handler)
    case .unsubscribe: Messaging.messaging().unsubscribe(fromTopic: pending.topic, completion: handler)
    }
  }

  // MARK: - FCM helpers
  func setFCMToken(_ token: String?) {
    cachedFCMToken = token
    unsubscribeFromLegacyGeneralTopicOnce()
    subscribeToTimezoneTopicIfNeeded()
  }

  /// Every install used to subscribe to a `general` topic that nothing in
  /// `functions/` ever published to. Devices stay subscribed server-side once
  /// they've asked, so drop it — otherwise a future broadcast on that topic would
  /// reach people who never opted into one.
  private func unsubscribeFromLegacyGeneralTopicOnce() {
    let key = "didUnsubscribeGeneralTopic"
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    enqueueUnsubscribe(topic: "general") {
      UserDefaults.standard.set(true, forKey: key)
    }
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
    guard last != topic else { return }

    if let last { enqueueUnsubscribe(topic: last) }
    enqueueSubscribe(topic: topic, persistKey: key)
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
    // Gives the reminder its mood buttons.
    content.categoryIdentifier = DailyCheckIn.category
    
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
    // Gives the reminder its mood buttons.
    content.categoryIdentifier = DailyCheckIn.category
    
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
