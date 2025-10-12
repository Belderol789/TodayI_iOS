//
//  MemoryService_Likes.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/11/25.
//

import FirebaseFirestore

extension MemoryService {
  
  /// Increment the `likes` counter of a memory by +1 in Firestore.
  /// - Parameters:
  ///   - ownerID: UID of the memory's owner (the user under `/users/{ownerID}`)
  ///   - memoryID: The memory document ID
  /// - Note: No SwiftData updates are performed. Fire-and-forget.
  static func like(
    ownerID: String,
    memoryID: String,
    db: Firestore = Firestore.firestore()
  ) async throws {
    let memRef = db.collection("users")
      .document(ownerID)
      .collection("memories")
      .document(memoryID)
    
    try await memRef.updateData([
      "likes": FieldValue.increment(Int64(1)),
      "updatedAt": FieldValue.serverTimestamp()
    ])
  }
  
  /// Convenience overload if you have the model (still no SwiftData write).
  static func like(
    memory: MemoryModel,
    db: Firestore = Firestore.firestore()
  ) async throws {
    try await like(ownerID: memory.userID, memoryID: memory.id, db: db)
  }
}
