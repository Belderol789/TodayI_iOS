//
//  MemoryService_Comment.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/13/25.
//

import FirebaseFirestore
import FirebaseAuth

extension MemoryService {
  /// Ensures a top-level comments hub document exists for this memory.
  /// Path: comments/{memoryID}
  static func ensureCommentsHub(
    memoryID: String,
    ownerID: String,
    isPublic: Bool,
    dayKey: String,
    db: Firestore = .firestore()
  ) async throws {
    let hub = db.collection("comments").document(memoryID)
    // Cheap & idempotent: create-or-merge; increment(0) guarantees numeric field.
    try await hub.setData([
      "memoryID": memoryID,
      "ownerID": ownerID,
      "isPublic": isPublic,
      "dayKey": dayKey,
      "commentCount": FieldValue.increment(Int64(0)),
      "updatedAt": FieldValue.serverTimestamp(),
      // createdAt will be overwritten on subsequent calls if we include it every time,
      // so omit it here to avoid churn. If you want a stable createdAt, use the txn version below.
    ], merge: true)
  }
  
  static func postComment(
    memoryID: String,
    text: String,
    username: String,
    db: Firestore = .firestore()
  ) async throws {
    guard
      let uid = Auth.auth().currentUser?.uid,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    
    let hub = db.collection("comments").document(memoryID)
    let ref = hub.collection("comments").document() // auto-id
    
    let data: [String: Any] = [
      "id": ref.documentID,
      "userID": uid,
      "username": username,
      "text": text,
      "createdAt": FieldValue.serverTimestamp()
    ]
    
    // Create the hub (if somehow missing) and add the comment
    try await hub.setData([
      "memoryID": memoryID,
      "commentCount": FieldValue.increment(Int64(0)),
      "updatedAt": FieldValue.serverTimestamp()
    ], merge: true)
    
    try await ref.setData(data)
    
    // Bump the thread counter
    try await hub.updateData([
      "commentCount": FieldValue.increment(Int64(1)),
      "updatedAt": FieldValue.serverTimestamp()
    ])
  }
}

extension MemoryService {
  /// Deletes a specific comment and decrements the count in its hub.
  /// Path: comments/{memoryID}/comments/{commentID}
  static func deleteComment(
    memoryID: String,
    commentID: String,
    db: Firestore = .firestore()
  ) async throws {
    guard let uid = Auth.auth().currentUser?.uid else {
      throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
    }
    
    let commentRef = db
      .collection("comments")
      .document(memoryID)
      .collection("comments")
      .document(commentID)
    
    // Optional: sanity check it exists and is yours (helps with clearer client logs)
    let snap = try await commentRef.getDocument()
    guard let data = snap.data(),
          let owner = data["userID"] as? String,
          owner == uid else {
      throw NSError(domain: "Rules", code: 403, userInfo: [NSLocalizedDescriptionKey: "Not the author or missing doc"])
    }
    
    try await commentRef.delete()
  }
}
