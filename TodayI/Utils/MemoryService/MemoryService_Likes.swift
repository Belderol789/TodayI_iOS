import FirebaseFirestore
import FirebaseAuth

extension MemoryService {
  /// Toggles the current user's like on a memory using arrayUnion/arrayRemove.
  /// Idempotent — safe to call even if the user already liked/unliked.
  /// Returns the new liked state (true = now liked).
  @discardableResult
  static func toggleLike(
    memory: MemoryModel,
    db: Firestore = .firestore()
  ) async throws -> Bool {
    guard let uid = Auth.auth().currentUser?.uid else { return false }
    let ref = db.collection("users").document(memory.userID)
      .collection("memories").document(memory.id)
    let isCurrentlyLiked = memory.likedBy.contains(uid)
    if isCurrentlyLiked {
      try await ref.updateData([
        "likedBy": FieldValue.arrayRemove([uid]),
        "likes":   FieldValue.increment(Int64(-1))
      ])
    } else {
      try await ref.updateData([
        "likedBy": FieldValue.arrayUnion([uid]),
        "likes":   FieldValue.increment(Int64(1))
      ])
    }
    return !isCurrentlyLiked
  }
}
