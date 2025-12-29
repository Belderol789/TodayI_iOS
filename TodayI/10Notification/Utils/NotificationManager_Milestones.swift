import Foundation
import FirebaseFirestore
import FirebaseAuth

extension NotificationManager {
  // MARK: - Realtime listener
  /// Listen to notifications in real-time
  @discardableResult
  func listenUserInbox(
    uid: String,
    limit: Int = 100,
    unreadOnly: Bool = false,
    onChange: @MainActor @escaping (_ items: [AppNotificationDTO], _ unread: Int) -> Void
  ) -> ListenerRegistration {
    let db = Firestore.firestore()
    var ref: Query = db.collection("users").document(uid)
      .collection("notifications")
      .order(by: "createdAt", descending: true)
      .limit(to: limit)
    
    // 🔍 Filter to unread only
    if unreadOnly {
      ref = ref.whereField("read", isEqualTo: false)
    }
    
    let listener = ref.addSnapshotListener { snap, err in
      if let err = err {
        print("Inbox listen error:", err)
        Task { @MainActor in onChange([], 0) }
        return
      }
      let docs = snap?.documents ?? []
      let items = docs.compactMap(AppNotificationDTO.init(doc:))
      let unread = items.filter { !$0.read }.count
      Task { @MainActor in onChange(items, unread) }
    }
    return listener
  }
  
  // MARK: - One-shot fetch
  /// Fetch the latest notifications once (for pull-to-refresh, manual reload, etc.)
  func fetchUserInboxOnce(
    uid: String,
    limit: Int = 100,
    unreadOnly: Bool = false
  ) async throws -> [AppNotificationDTO] {
    let db = Firestore.firestore()
    var query: Query = db.collection("users").document(uid)
      .collection("notifications")
      .order(by: "createdAt", descending: true)
      .limit(to: limit)
    
    // 🔍 Filter to unread only if needed
    if unreadOnly {
      query = query.whereField("read", isEqualTo: false)
    }
    
    let snap = try await query.getDocuments()
    return snap.documents.compactMap(AppNotificationDTO.init(doc:))
  }
  
  // MARK: - Mark read helpers
  func markNotificationRead(uid: String, id: String) {
    let db = Firestore.firestore()
    db.collection("users").document(uid)
      .collection("notifications").document(id)
      .setData(["read": true], merge: true)
  }
  
  func markNotificationsRead(uid: String, ids: [String]) {
    let db = Firestore.firestore()
    let batch = db.batch()
    let col = db.collection("users").document(uid).collection("notifications")
    ids.forEach { batch.setData(["read": true], forDocument: col.document($0), merge: true) }
    batch.commit { err in
      if let err = err { print("markNotificationsRead error:", err) }
    }
  }
  
  // MARK: - Simple one-liner wrapper
  /// Convenience: get all notifications (unread or all)
  func getUserNotifications(uid: String, unreadOnly: Bool = false, limit: Int = 100) async -> [AppNotificationDTO] {
    do {
      return try await fetchUserInboxOnce(uid: uid, limit: limit, unreadOnly: unreadOnly)
    } catch {
      print("getUserNotifications failed:", error)
      return []
    }
  }
}
