import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class CommentThreadViewModel: ObservableObject {
  @Published var comments: [CommentDTO] = []
  @Published var newComment: String = ""
  @Published var isLoading = false
  
  private let memoryID: String
  private let db = Firestore.firestore()
  
  init(memoryID: String) {
    self.memoryID = memoryID
  }
  
  func loadComments() async {
    isLoading = true
    defer { isLoading = false }
    
    do {
      let snap = try await db
        .collection("comments")
        .document(memoryID)
        .collection("comments")
        .order(by: "createdAt", descending: false)
        .getDocuments()
      
      comments = snap.documents.compactMap { CommentDTO(doc: $0) }
    } catch {
      print("⚠️ Failed to load comments:", error)
      comments = []
    }
  }
  
  func postComment() async {
    let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    
    guard let uid = Auth.auth().currentUser?.uid else {
      print("⚠️ No logged-in user; cannot post comment.")
      return
    }
    
    let username = Auth.auth().currentUser?.displayName ?? "Anonymous"
    let commentData: [String: Any] = [
      "userID": uid,
      "username": username,
      "text": trimmed,
      "createdAt": FieldValue.serverTimestamp()
    ]
    
    do {
      try await db
        .collection("comments")
        .document(memoryID)
        .collection("comments")
        .addDocument(data: commentData)
      newComment = ""
      await loadComments()
    } catch {
      print("⚠️ Failed to post comment:", error)
    }
  }
}
