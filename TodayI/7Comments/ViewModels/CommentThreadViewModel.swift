import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class CommentThreadViewModel: ObservableObject {
  @Published var comments: [CommentDTO] = []
  @Published var newComment: String = ""
  @Published var isLoading = false
  @Published var isLoadingMore = false
  @Published var reachedEnd = false

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

  func postComment(username: String?) async {
    let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
    let name = username ?? Auth.auth().currentUser?.displayName ?? "Anonymous"
    let tempID = UUID().uuidString
    let optimistic = CommentDTO(id: tempID, userID: uid, username: name,
                                text: trimmed, createdAt: Date())

    // Show immediately — don't wait for Firestore
    comments.append(optimistic)
    newComment = ""

    let data: [String: Any] = [
      "userID": uid,
      "username": name,
      "text": trimmed,
      "createdAt": FieldValue.serverTimestamp()
    ]
    do {
      let ref = try await db
        .collection("comments").document(memoryID)
        .collection("comments").addDocument(data: data)
      // Swap temp ID for the real Firestore document ID
      if let idx = comments.firstIndex(where: { $0.id == tempID }) {
        comments[idx] = CommentDTO(id: ref.documentID, userID: uid, username: name,
                                   text: trimmed, createdAt: optimistic.createdAt)
      }
    } catch {
      // Roll back the optimistic insert
      comments.removeAll { $0.id == tempID }
      newComment = trimmed
      print("⚠️ Failed to post comment:", error)
    }
  }
}
