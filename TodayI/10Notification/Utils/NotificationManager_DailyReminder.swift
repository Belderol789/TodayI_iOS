import Foundation

extension NotificationManager {

  // MARK: - Daily reminder (the one switch)
  //
  // There used to be two daily reminders that knew nothing about each other: the first-post
  // prompt subscribed the device to the server's 8pm FCM topic, and Settings → Daily
  // Reminder scheduled a separate *local* notification. Accepting the prompt never touched
  // the Settings switch, turning that switch off never stopped the server push, and turning
  // it on doubled up at 8pm. Now there is one reminder — local — and both the prompt and
  // Settings drive it through here, through the same `UserDefaults` keys Settings'
  // `@AppStorage` reads, so the switch always shows what is actually scheduled.
  //
  // Local beats the server push for this: it fires at the time each person picks, works
  // offline, and covers half-hour time zones the topic list can't. The world-mood push at
  // 6pm stays server-side, because its content changes every day.

  static let reminderEnabledKey = "dailyReminderEnabled"
  static let reminderHourKey = "dailyReminderHour"
  static let reminderMinuteKey = "dailyReminderMinute"
  static let reminderID = "daily-reminder"

  /// Turns the daily reminder on (at the saved time, 8pm by default) or off.
  func setDailyReminder(enabled: Bool) async {
    let defaults = UserDefaults.standard
    defaults.set(enabled, forKey: Self.reminderEnabledKey)
    guard enabled else {
      cancel(id: Self.reminderID)
      return
    }
    let hour = defaults.object(forKey: Self.reminderHourKey) as? Int ?? 20
    let minute = defaults.object(forKey: Self.reminderMinuteKey) as? Int ?? 0
    do {
      try await rescheduleDaily(
        id: Self.reminderID,
        hour: hour,
        minute: minute,
        title: "How are you feeling today?",
        body: "Take a moment to log your mood in TodayI."
      )
    } catch {
      // Not authorised: the switch can't promise a reminder iOS won't deliver.
      print("⚠️ Daily reminder not scheduled:", error)
      defaults.set(false, forKey: Self.reminderEnabledKey)
    }
  }

  /// Moves anyone still on the server's 8pm topic to the local reminder, once.
  ///
  /// They opted in through the old prompt, so they keep getting reminded — at the same
  /// 8pm — instead of silently losing it when the topic is dropped. The topic key is only
  /// removed once FCM confirms the unsubscribe, so a failed attempt retries next launch.
  func migrateServerReminderToLocalOnce() async {
    let topicKey = "lastTZTopic_daily8pm"
    guard let topic = UserDefaults.standard.string(forKey: topicKey) else { return }
    if !UserDefaults.standard.bool(forKey: Self.reminderEnabledKey) {
      await setDailyReminder(enabled: true)
    }
    enqueueUnsubscribe(topic: topic) {
      UserDefaults.standard.removeObject(forKey: topicKey)
    }
  }
}
