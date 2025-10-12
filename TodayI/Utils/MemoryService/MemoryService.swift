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
  
  // MARK: - Existing API (unchanged behavior + single new call)
  static func postMemory(_ memory: MemoryModel, db: Firestore = Firestore.firestore()) async throws {
    LoggerManager.instance.logFirebaseCall()
    guard !memory.userID.isEmpty else { throw MemoryUploadError.missingUserID }
    
    let userDoc  = db.collection("users").document(memory.userID)
    let memRef   = userDoc.collection("memories").document(memory.id)
    
    // Normalize the day key for the DateModel doc id (UTC-safe)
    let dayKey = Date().formattedDayKeyLocal()
    let dateRef = userDoc.collection("dates").document(dayKey)
    
    // --- Memory payload (omit local-only paths) ---
    let memData: [String: Any] = [
      "id": memory.id,
      "userID": memory.userID,
      "username": memory.username,
      "date": memory.date,                    // author local day start instant
      "dayKey": dayKey,
      // optional
      "authorTZ": memory.authorTZ,
      
      "mood": memory.mood.rawValue,
      "journalText": memory.journalText,
      "likes": memory.likes,
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
    // Write memory first, then upsert the date entry
    try await memRef.setData(memData, merge: true)
    try await dateRef.setData(dateData, merge: true)
    
    // NEW: bump global mood tally for that day in top-level "moods/{dayKey}"
    try await incrementDailyMoodTally(for: memory, db: db)
    try await MemoryService.ensureCommentsHub(
      memoryID: memory.id,
      ownerID: memory.userID,
      isPublic: memory.isPublic,
      dayKey: dayKey
    )
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
}


