import FirebaseFirestore

extension MemoryService {
  /// Update the public/private flag of a memory.
  /// - Note: Rules must allow owner updates (your current rules do).
  static func updatePrivacy(
    userID: String,
    memoryID: String,
    isPublic: Bool,
    db: Firestore = .firestore()
  ) async throws {
    let ref = db.collection("users").document(userID)
      .collection("memories").document(memoryID)
    
    try await ref.updateData([
      "isPublic": isPublic,
      "updatedAt": FieldValue.serverTimestamp()
    ])
  }
  
  /// Convenience overload if you already have the model.
  static func updatePrivacy(
    for memory: MemoryModel,
    isPublic: Bool,
    db: Firestore = .firestore()
  ) async throws {
    try await updatePrivacy(userID: memory.userID, memoryID: memory.id, isPublic: isPublic, db: db)
  }
}
