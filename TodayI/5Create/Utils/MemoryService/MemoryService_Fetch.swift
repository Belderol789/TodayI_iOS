//
//  MemoryService_Fetch.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/11/25.
//

import FirebaseFirestore

extension MemoryService {
  /// Fetches all lightweight date entries for a user.
  static func fetchDates(for userID: String, db: Firestore = Firestore.firestore()) async throws -> [DateDTO] {
    LoggerManager.instance.logFirebaseCall()
    let snapshot = try await db
      .collection("users")
      .document(userID)
      .collection("dates")
      .getDocuments()
    
    return snapshot.documents.compactMap { DateDTO(doc: $0) }
  }
  
  /// Fetches all memories for a user on a given dayKeyLocal.
  static func fetchMemories(for userID: String, dayKeyLocal: String, db: Firestore = Firestore.firestore()) async throws -> [MemoryDTO] {
    LoggerManager.instance.logFirebaseCall()
    let snapshot = try await db.collection("users").document(userID)
      .collection("memories")
      .whereField("dayKeyLocal", isEqualTo: dayKeyLocal)
      .getDocuments()
    
    return snapshot.documents.compactMap { doc in
      try? doc.data(as: MemoryDTO.self)   // Firestore Decodable support
    }
  }
}
