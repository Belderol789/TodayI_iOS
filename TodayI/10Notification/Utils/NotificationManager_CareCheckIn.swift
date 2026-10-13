import Foundation
import UserNotifications

extension NotificationManager {

  // MARK: - Care check-in
  //
  // Offered on the self-harm support sheet. An entry like that is kept off the Global feed,
  // which protects strangers but can leave the writer feeling unheard, so the sheet offers
  // a single gentle check-in the next morning — opt-in, on the device, nothing sent to a
  // server. The notification never quotes or hints at the entry: a lock screen is
  // readable by whoever is holding the phone.

  static let careCheckInID = "care-check-in"
  private static let careCheckInHour = 10
  /// So an entry written at 1am is followed up that morning, not 33 hours later.
  private static let careCheckInMinimumWait: TimeInterval = 4 * 3600

  /// Schedules the check-in, asking for permission if it hasn't been asked yet. Returns
  /// when it will arrive, or `nil` if notifications aren't allowed.
  func scheduleCareCheckIn(now: Date = Date()) async -> Date? {
    guard await configure() else { return nil }

    let fireDate = Self.careCheckInDate(after: now)
    let content = UNMutableNotificationContent()
    content.title = "Checking in"
    content.body = "How are you doing today? Whatever you're feeling, you can write it down."
    content.sound = .default

    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
    // The same identifier replaces a pending one, so asking twice still means one check-in.
    let request = UNNotificationRequest(
      identifier: Self.careCheckInID,
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    )
    do {
      try await UNUserNotificationCenter.current().add(request)
      print("💛 Care check-in scheduled for", fireDate)
      return fireDate
    } catch {
      print("❌ Could not schedule care check-in:", error)
      return nil
    }
  }

  /// When a check-in already asked for will arrive, so the sheet can say so instead of
  /// offering it again.
  func pendingCareCheckInDate() async -> Date? {
    let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
    let trigger = pending.first { $0.identifier == Self.careCheckInID }?.trigger
    return (trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
  }

  /// The next 10am at least four hours away.
  static func careCheckInDate(after now: Date, calendar: Calendar = .current) -> Date {
    var candidate = calendar.date(bySettingHour: careCheckInHour, minute: 0, second: 0, of: now)
      ?? now.addingTimeInterval(careCheckInMinimumWait)
    while candidate.timeIntervalSince(now) < careCheckInMinimumWait {
      guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
      candidate = next
    }
    return candidate
  }
}
