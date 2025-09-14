import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftData
import Combine

@MainActor
final class AuthStore: ObservableObject {
  @Published private(set) var userID: String?
  @Published private(set) var username: String?
  @Published private(set) var isAnonymous: Bool = true
  @Published private(set) var email: String?
  
  private let db = Firestore.firestore()
  private let context: ModelContext
  
  init(context: ModelContext) {
    self.context = context
    Task { await ensureSignedIn() }
  }
  
  // MARK: - Entry point
  func ensureSignedIn() async {
    if let current = Auth.auth().currentUser {
      await loadOrCreateProfile(for: current)
    } else {
      do {
        let result = try await Auth.auth().signInAnonymously()
        await loadOrCreateProfile(for: result.user)
      } catch {
        print("Anonymous sign-in failed:", error)
      }
    }
  }
  
  // MARK: - Profile bootstrap
  private func loadOrCreateProfile(for user: FirebaseAuth.User) async {
    let uid = user.uid
    let userDoc = db.collection("users").document(uid)
    
    do {
      let snap = try await userDoc.getDocument()
      if snap.exists, let data = snap.data() {
        // Use remote values
        let uname = data["username"] as? String ?? Self.defaultUsername(for: uid)
        let email = data["email"] as? String
        let isAnon = data["isAnonymous"] as? Bool ?? user.isAnonymous
        
        // Update local cache
        upsertLocalUser(uid: uid, username: uname, email: email, isAnonymous: isAnon)
        publish(uid: uid, username: uname, email: email, isAnonymous: isAnon)
      } else {
        // Create a new profile
        let uname = Self.defaultUsername(for: uid)
        let payload: [String: Any] = [
          "uid": uid,
          "username": uname,
          "email": user.email as Any,
          "isAnonymous": user.isAnonymous,
          "photoURL": user.photoURL?.absoluteString as Any,
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp()
        ]
        try await userDoc.setData(payload)
        upsertLocalUser(uid: uid, username: uname, email: user.email, isAnonymous: user.isAnonymous)
        publish(uid: uid, username: uname, email: user.email, isAnonymous: user.isAnonymous)
      }
    } catch {
      print("Failed to load/create user profile:", error)
      // Fallback to local default username
      let uname = Self.defaultUsername(for: uid)
      upsertLocalUser(uid: uid, username: uname, email: user.email, isAnonymous: user.isAnonymous)
      publish(uid: uid, username: uname, email: user.email, isAnonymous: user.isAnonymous)
    }
  }
  
  // MARK: - Username editing
  func updateUsername(_ newName: String) async {
    guard let uid = userID else { return }
    do {
      try await db.collection("users").document(uid).updateData([
        "username": newName,
        "updatedAt": FieldValue.serverTimestamp()
      ])
      // Local cache + state
      if let local = try? fetchLocalUser(uid: uid) {
        local.username = newName
        local.updatedAt = .now
        try? context.save()
      }
      self.username = newName
    } catch {
      print("Update username failed:", error)
    }
  }
  
  // MARK: - Credential linking (keeps same uid)
  // Email/Password example:
  func linkEmailPassword(email: String, password: String) async throws {
    guard let user = Auth.auth().currentUser else { return }
    let cred = EmailAuthProvider.credential(withEmail: email, password: password)
    let result = try await user.link(with: cred) // <— uid stays the same
    await loadOrCreateProfile(for: result.user)  // refresh local+remote
  }
  
  // Sign in with Apple example (you’ll supply credential from ASAuthorization):
  func linkApple(credential: OAuthCredential) async throws {
    guard let user = Auth.auth().currentUser else { return }
    let result = try await user.link(with: credential) // same uid
    await loadOrCreateProfile(for: result.user)
  }
  
  // MARK: - Helpers
  private func upsertLocalUser(uid: String, username: String, email: String?, isAnonymous: Bool) {
    do {
      let fetch = FetchDescriptor<UserModel>(predicate: #Predicate { $0.id == uid })
      if let existing = try context.fetch(fetch).first {
        existing.username = username
        existing.email = email
        existing.isAnonymous = isAnonymous
        existing.updatedAt = .now
      } else {
        let model = UserModel(id: uid, username: username, email: email, isAnonymous: isAnonymous)
        context.insert(model)
      }
      try context.save()
    } catch {
      print("SwiftData upsert user failed:", error)
    }
  }
  
  private func fetchLocalUser(uid: String) throws -> UserModel? {
    let fetch = FetchDescriptor<UserModel>(predicate: #Predicate { $0.id == uid })
    return try context.fetch(fetch).first
  }
  
  private func publish(uid: String, username: String?, email: String?, isAnonymous: Bool) {
    self.userID = uid
    self.username = username
    self.email = email
    self.isAnonymous = isAnonymous
  }
  
  // Example default username generator: "guest-4F7C"
  static func defaultUsername(for uid: String) -> String {
    let suffix = uid.suffix(4).uppercased()
    return "guest-\(suffix)"
  }
}
