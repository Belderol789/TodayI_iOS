//
//  MemoryService_Fetch.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/11/25.
//

import FirebaseFirestore

extension MemoryService {
  /// Fetches a single memory by id. Used when opening a notification, where the
  /// milestone names a `postId` but the device may not have that day cached.
  static func fetchMemory(userID: String,
                          memoryID: String,
                          db: Firestore = Firestore.firestore()) async throws -> MemoryDTO? {
    LoggerManager.instance.logFirebaseCall()
    let doc = try await db.collection("users").document(userID)
      .collection("memories").document(memoryID).getDocument()
    guard doc.exists else { return nil }
    return try? doc.data(as: MemoryDTO.self)
  }

  /// Fetches all lightweight date entries for a user.
  /// Fetches a user's calendar days.
  ///
  /// `since` turns this into a delta sync: only days whose `updatedAt` moved after that
  /// point come back. `dates/{dayKey}` gets `updatedAt: FieldValue.serverTimestamp()` on
  /// every `postMemory` write — including a *second* mood added to an already-synced
  /// day — so a delta catches both a brand-new day and an existing one that changed,
  /// which a filter on `date` (the day's own calendar date, never updated) could not.
  /// `since: nil` is a full fetch, used for the very first sync of an account and for an
  /// explicit pull-to-refresh.
  static func fetchDates(
    for userID: String,
    since: Date? = nil,
    db: Firestore = Firestore.firestore()
  ) async throws -> [DateDTO] {
    LoggerManager.instance.logFirebaseCall()
    print("Kem Fetch dates \(userID)", since.map { "since \($0)" } ?? "(full)")
    var query: Query = db
      .collection("users")
      .document(userID)
      .collection("dates")
    if let since {
      query = query.whereField("updatedAt", isGreaterThan: Timestamp(date: since))
    }
    let snapshot = try await query.getDocuments()
    
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
