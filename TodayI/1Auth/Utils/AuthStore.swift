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
  
  let db = Firestore.firestore()
  let context: ModelContext
  
  var authHandle: AuthStateDidChangeListenerHandle?
  
  init(context: ModelContext) {
    self.context = context
    Task {
      startListening()
    }
  }
  
  deinit {
    if let h = authHandle { Auth.auth().removeStateDidChangeListener(h) }
  }
  
  func publish(uid: String, username: String?, email: String?, isAnonymous: Bool, photoURL: String? = nil) {
    self.userID = uid
    self.username = username
    self.email = email
    self.isAnonymous = isAnonymous
    self.photoURL = photoURL
    
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
