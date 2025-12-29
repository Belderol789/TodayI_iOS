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
    print("Kem Fetch dates \(userID)")
    let snapshot = try await db
      .collection("users")
      .document(userID)
      .collection("dates")
      .getDocuments()
    
    return snapshot.documents.compactMap { DateDTO(doc: $0) }
  }
  
  /// Fetches all memories for a user on a given dayKeyLocal.
  static func fetchMemories(for userID: String,
                            dayKeyLocal: String,
                            db: Firestore = Firestore.firestore()) async throws -> [MemoryDTO] {
    LoggerManager.instance.logFirebaseCall()
    print("Kem Fetch memories \(userID)")
    let snapshot = try await db.collection("users")
      .document(userID)
      .collection("memories")
      .whereField("dayKey", isEqualTo: dayKeyLocal)
      .getDocuments()
    
    print("Existing documents: \(snapshot.documents.count)")
    
    let items: [MemoryDTO] = snapshot.documents.compactMap { doc in
      do {
        let dto = try doc.data(as: MemoryDTO.self)
        return dto
      } catch {
        print("❌ Decode error for doc \(doc.documentID):", error)
        return nil
      }
    }
    
    print("MemoryDTO items fetched \(items.count)")
    return items   // ← REQUIRED
  }
}
