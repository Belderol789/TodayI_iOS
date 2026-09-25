import UIKit
import FirebaseAuth
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleSignIn

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
  
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    print("👋 AppDelegate didFinishLaunching")
    FirebaseApp.configure()
    // Crashlytics only exists after configure() — send anything TodayIApp.init buffered.
    StartupDiagnostics.flush()
    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self
    // Must be registered before any notification carrying this category arrives,
    // otherwise iOS shows it with no buttons.
    NotificationManager.shared.registerNotificationCategories()
    return true
  }
  
  func application(_ application: UIApplication,
                   didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    print("APNs token length:", deviceToken.count)
    Messaging.messaging().apnsToken = deviceToken
    // Topics queued before this point can now be subscribed — see the gate in
    // NotificationManager. Without this, a cold launch lost every subscription.
    NotificationManager.shared.apnsTokenDidRegister()
  }
  
  func application(_ application: UIApplication,
                   didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("APNs registration failed:", error)
  }
  
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    print("Tapped notification:", response.notification.request.identifier,
          response.notification.request.content.userInfo,
          "action:", response.actionIdentifier)
    // A mood button writes the entry and leaves the user where they were; anything
    // else falls through to the default open behaviour.
    Task { @MainActor in
      await NotificationManager.shared.handleNotificationResponse(response)
      completionHandler()
    }
  }
  
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
    print("Will present local/remote:", notification.request.identifier,
          notification.request.content.userInfo)
    completion([.banner, .list, .sound])
  }
  
  func application(_ application: UIApplication,
                   didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                   fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    NotificationManager.shared.handleRemoteDataPush(userInfo, completion: completionHandler)
  }
  
  func application(_ app: UIApplication, open url: URL,
                   options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    GIDSignIn.sharedInstance.handle(url)
  }

  // FCM registration token updated
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("FCM token:", fcmToken ?? "nil")
    NotificationManager.shared.setFCMToken(fcmToken)
    if let uid = Auth.auth().currentUser?.uid {
      NotificationManager.shared.subscribeUserTopic(uid: uid)
    }
  }
}
