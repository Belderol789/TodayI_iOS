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
    try await db.collection("comments").document(memoryID)
      .setData(commentsHubPayload(memoryID: memoryID, ownerID: ownerID,
                                  isPublic: isPublic, dayKey: dayKey),
               merge: true)
  }

  /// Hub fields as a mergeable dictionary so `postMemory` can batch this write
  /// rather than spending a separate round trip on it.
  /// Cheap & idempotent: create-or-merge; `increment(0)` guarantees a numeric field.
  /// `createdAt` is deliberately omitted — including it would rewrite the value on
  /// every call.
  static func commentsHubPayload(
    memoryID: String,
    ownerID: String,
    isPublic: Bool,
    dayKey: String
  ) -> [String: Any] {
    [
      "memoryID": memoryID,
      "ownerID": ownerID,
      "isPublic": isPublic,
      "dayKey": dayKey,
      "commentCount": FieldValue.increment(Int64(0)),
      "updatedAt": FieldValue.serverTimestamp()
    ]
  }
  
  static func postComment(
    memoryID: String,
    text: String,
    username: String,
    photoURL: String? = nil,
    db: Firestore = .firestore()
  ) async throws {
    guard
      let uid = Auth.auth().currentUser?.uid,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    
    let hub = db.collection("comments").document(memoryID)
    let ref = hub.collection("comments").document() // auto-id
    
    var data: [String: Any] = [
      "id": ref.documentID,
      "userID": uid,
      "username": username,
      "text": text,
      "createdAt": FieldValue.serverTimestamp()
    ]
    // Keep in sync with CommentThreadViewModel.postComment, which is the live path.
    if let photoURL, !photoURL.isEmpty { data["photoURL"] = photoURL }
    
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
