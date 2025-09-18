//
//  FirebaseManager.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/5/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

enum MemoryUploadError: Error {
  case missingUserID
}

struct MemoryService {
  
  // MARK: - New helper: global per-day mood tally in top-level "moods/{dayKey}"
  private static func incrementDailyMoodTally(for memory: MemoryModel,
                                              db: Firestore = Firestore.firestore()) async throws {
    // Normalize keys/timestamps
    let dayKey = Self.dayKeyString(for: memory.date)
    let startOfDay = Calendar.current.startOfDay(for: memory.date)
    
    // moods/{dayKey}
    let moodsDoc  = db.collection("moods").document(dayKey)
    let moodField = String(describing: memory.mood).lowercased() // e.g. "angry", "sad"
    let incKey    = "tally.\(moodField)"                         // nested dict key
    
    _ = try await db.runTransaction { txn, errorPtr -> Any? in
      let snap: DocumentSnapshot
      do {
        snap = try txn.getDocument(moodsDoc)
      } catch {
        errorPtr?.pointee = error as NSError
        return nil
      }
      
      if !snap.exists {
        // First write — stamp base metadata; no need to pre-seed all moods
        txn.setData([
          "date": startOfDay,
          "createdAt": FieldValue.serverTimestamp()
        ], forDocument: moodsDoc, merge: true)
      }
      
      txn.updateData([
        incKey: FieldValue.increment(Int64(1)),
        "updatedAt": FieldValue.serverTimestamp()
      ], forDocument: moodsDoc)
      
      return nil
    }
  }
  
  // MARK: - Existing API (unchanged behavior + single new call)
  static func postMemory(_ memory: MemoryModel, db: Firestore = Firestore.firestore()) async throws {
    LoggerManager.instance.logFirebaseCall()
    guard !memory.userID.isEmpty else { throw MemoryUploadError.missingUserID }
    
    let userDoc  = db.collection("users").document(memory.userID)
    let memRef   = userDoc.collection("memories").document(memory.id)
    
    // Normalize the day key for the DateModel doc id (UTC-safe)
    let dayKey = Self.dayKeyString(for: memory.date)
    let dateRef = userDoc.collection("dates").document(dayKey)
    
    // --- Memory payload (omit local-only paths) ---
    let memData: [String: Any] = [
      "id": memory.id,
      "userID": memory.userID,
      "username": memory.username,
      "date": memory.date,                    // author local day start instant
      "dayKeyLocal": memory.dayKeyLocal,      // "yyyy-MM-dd" (author tz)
      "dayKeyUTC": memory.dayKeyUTC as Any,   // optional
      "authorTZ": memory.authorTZ,
      
      "mood": memory.mood.rawValue,
      "journalText": memory.journalText,
      "remoteImagePaths": memory.remoteImagePaths,
      "videoRemoteURL": memory.videoRemoteURL as Any,
      "linkURL": memory.linkURL as Any,
      "isPublic": memory.isPublic,
      
      // prefer server timestamps for consistency in global queries
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp()
    ]
    
    // --- DateModel payload (server-merge, add mood) ---
    let startOfDay = Calendar.current.startOfDay(for: memory.date)
    let dateData: [String: Any] = [
      "date": startOfDay,                       // Timestamp
      "moodRaws": FieldValue.arrayUnion([memory.mood.rawValue]),
      "updatedAt": FieldValue.serverTimestamp()
    ]
    
    MemoryService.assertMemoryPayload(memory)
    print("User \(memory.userID) user \(Auth.auth().getUserID())")
    // Write memory first, then upsert the date entry
    try await memRef.setData(memData, merge: true)
    try await dateRef.setData(dateData, merge: true)
    
    // NEW: bump global mood tally for that day in top-level "moods/{dayKey}"
    try await incrementDailyMoodTally(for: memory, db: db)
  }
  
  private static func assertMemoryPayload(_ m: MemoryModel) {
    func isHttps(_ s: String?) -> Bool { s?.hasPrefix("http://") == true || s?.hasPrefix("https://") == true }
    let usernameOK = !m.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && m.username.count <= 64
    let moodOK     = true // rules now accept String OR Int; rawValue ok
    let imgsOK     = m.remoteImagePaths.allSatisfy { $0.hasPrefix("http://") || $0.hasPrefix("https://") } && m.remoteImagePaths.count <= 12
    let linkOK     = m.linkURL == nil || isHttps(m.linkURL)
    let videoOK    = m.videoRemoteURL == nil || isHttps(m.videoRemoteURL)
    
    
    print("Rules preflight — usernameOK:", usernameOK,
          "moodOK:", moodOK, "imgsOK:", imgsOK, "linkOK:", linkOK, "videoOK:", videoOK)
  }
  
  /// yyyy-MM-dd (UTC) string to keep date docs stable across timezones.
  private static func dayKeyString(for date: Date) -> String {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let comps = utc.dateComponents([.year, .month, .day], from: date)
    let y = comps.year!, m = comps.month!, d = comps.day!
    // zero-pad: 2025-09-14
    return String(format: "%04d-%02d-%02d", y, m, d)
  }
}

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

