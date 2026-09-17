import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class CommentThreadViewModel: ObservableObject {
  @Published var comments: [CommentDTO] = []
  @Published var newComment: String = "" { didSet { enforceLimit() } }
  @Published var isLoading = false
  @Published var isLoadingMore = false
  @Published var reachedEnd = false

  /// Mirrors the Firestore rule on `comments/{memoryID}/comments/{commentID}`,
  /// which rejects a create when `text.size() > 1000`. Keep the two in sync —
  /// without the client cap an over-long comment is denied with no UI feedback.
  let maxChars: Int = 1000
  @Published private(set) var remaining: Int = 1000

  private let memoryID: String
  private let db = Firestore.firestore()
  private let pageSize = 10
  private var cursor: DocumentSnapshot?

  private var baseQuery: Query {
    db.collection("comments")
      .document(memoryID)
      .collection("comments")
      .order(by: "createdAt", descending: false)
      .limit(to: pageSize)
  }

  init(memoryID: String) {
    self.memoryID = memoryID
  }

  func loadComments() async {
    isLoading = true
    cursor = nil
    reachedEnd = false
    defer { isLoading = false }
    do {
      let snap = try await baseQuery.getDocuments()
      comments = snap.documents.compactMap { CommentDTO(doc: $0) }
      cursor = snap.documents.last
      reachedEnd = snap.documents.count < pageSize
    } catch {
      print("⚠️ Failed to load comments:", error)
      comments = []
    }
  }

  func loadMore() async {
    guard !isLoadingMore, !reachedEnd, let cursor else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let snap = try await baseQuery.start(afterDocument: cursor).getDocuments()
      let new = snap.documents.compactMap { CommentDTO(doc: $0) }
      comments.append(contentsOf: new)
      self.cursor = snap.documents.last
      reachedEnd = snap.documents.count < pageSize
    } catch {
      print("⚠️ Failed to load more comments:", error)
    }
  }

  func postComment(username: String?, photoURL: String? = nil) async {
    let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
    let name = username ?? Auth.auth().currentUser?.displayName ?? "Anonymous"
    let photo = (photoURL?.isEmpty ?? true) ? nil : photoURL
    let tempID = UUID().uuidString
    let optimistic = CommentDTO(id: tempID, userID: uid, username: name,
                                text: trimmed, createdAt: Date(), photoURL: photo)

    // Show immediately — don't wait for Firestore
    comments.append(optimistic)
    newComment = ""

    var data: [String: Any] = [
      "userID": uid,
      "username": name,
      "text": trimmed,
      "createdAt": FieldValue.serverTimestamp()
    ]
    // Extra keys are fine: the Firestore rule validates the required fields by type
    // but doesn't restrict the key set with hasOnly.
    if let photo { data["photoURL"] = photo }
    do {
      // One batch instead of three round trips (hub create-or-merge → add comment →
      // bump the hub counter). The comment's id is generated client-side so the
      // document reference exists before the write.
      let hub = db.collection("comments").document(memoryID)
      let ref = hub.collection("comments").document()
      let batch = db.batch()
      batch.setData(data, forDocument: ref)
      batch.setData([
        "memoryID": memoryID,
        "commentCount": FieldValue.increment(Int64(1)),
        "updatedAt": FieldValue.serverTimestamp()
      ], forDocument: hub, merge: true)
      try await batch.commit()
      // Swap temp ID for the real Firestore document ID
      if let idx = comments.firstIndex(where: { $0.id == tempID }) {
        comments[idx] = CommentDTO(id: ref.documentID, userID: uid, username: name,
                                   text: trimmed, createdAt: optimistic.createdAt,
                                   photoURL: photo)
      }
    } catch {
      // Roll back the optimistic insert
      comments.removeAll { $0.id == tempID }
      newComment = trimmed
      print("⚠️ Failed to post comment:", error)
    }
  }

  // MARK: - Character limit

  private func enforceLimit() {
    if newComment.count > maxChars {
      newComment = String(newComment.prefix(maxChars))
    }
    remaining = max(0, maxChars - newComment.count)
  }
}
