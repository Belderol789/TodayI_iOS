import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftData
import Combine

@MainActor
final class AuthStore: ObservableObject {
  
  var isLoggedIn: Bool { userID != nil }                // any firebase user
  var isGuest: Bool { isAnonymous }                     // specifically anonymous
  var isRegisteredUser: Bool { isLoggedIn && !isGuest } // upgraded account
  
  @Published private(set) var userID: String?
  @Published private(set) var isAnonymous: Bool = true
  @Published private(set) var email: String?
  @Published var profileImage: UIImage?
  @Published var photoURL: String?
  @Published var username: String?
  /// True once the first auth state has been resolved (signed-in or anonymous).
  /// Use this to gate the main UI so a blank screen never shows on launch.
  @Published var isSessionReady: Bool = false
  /// Set to true by an admin via Firebase Console → disables public posting.
  @Published private(set) var isRestricted: Bool = false
  /// Set to true by any view that needs to hide the custom tab bar (e.g. CommentThreadView).
  @Published var hideTabBar: Bool = false
  
  let db = Firestore.firestore()
  let context: ModelContext
  
  var authHandle: AuthStateDidChangeListenerHandle?
  
  init(context: ModelContext) {
    self.context = context
    Task {
      startListening()
      await ensureSignedIn()
    }
  }
  
  deinit {
    if let h = authHandle { Auth.auth().removeStateDidChangeListener(h) }
  }
  
  func publish(uid: String, username: String?, email: String?, isAnonymous: Bool, photoURL: String? = nil, isRestricted: Bool = false) {
    self.userID = uid
    self.username = username
    self.email = email
    self.isAnonymous = isAnonymous
    self.photoURL = photoURL
    self.isRestricted = isRestricted
    isSessionReady = true

    // ✅ Try to load the cached profile image
    loadLocalProfileImageIfAvailable(for: uid)
  }
  
  private func loadLocalProfileImageIfAvailable(for uid: String) {
    let filename = "profile_\(uid).jpg"
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    let fileURL = directory?.appendingPathComponent(filename)
    
    if let fileURL,
       FileManager.default.fileExists(atPath: fileURL.path),
       let image = UIImage(contentsOfFile: fileURL.path) {
      self.profileImage = image
    }
  }


  // Example default username generator: "guest-4F7C"
  static func defaultUsername(for uid: String) -> String {
    let suffix = uid.suffix(4).uppercased()
    return "guest-\(suffix)"
  }
}
