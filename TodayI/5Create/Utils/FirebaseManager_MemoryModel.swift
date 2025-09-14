//
//  FirebaseManager.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/5/25.
//

import Foundation
import FirebaseFirestore

enum MemoryUploadError: Error {
  case missingUserID
}

struct MemoryService {
  /// Upload a single MemoryModel to Firestore and upsert its DateModel under the same user.
  /// - Throws: `MemoryUploadError.missingUserID` if `memory.userID` is empty, or Firestore errors.
  static func postMemory(_ memory: MemoryModel, db: Firestore = Firestore.firestore()) async throws {
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
      "date": memory.date,
      "mood": memory.mood.rawValue,
      "journalText": memory.journalText,
      "remoteImagePaths": memory.remoteImagePaths,
      "videoRemoteURL": memory.videoRemoteURL as Any,   // 👈
      "linkURL": memory.linkURL as Any,                 // 👈
      "isPublic": memory.isPublic,
      "createdAt": memory.createdAt,
      "updatedAt": memory.updatedAt
    ]
    
    // --- DateModel payload (server-merge, add mood) ---
    let startOfDay = Calendar.current.startOfDay(for: memory.date)
    let dateData: [String: Any] = [
      "date": startOfDay,                       // Timestamp
      "moodRaws": FieldValue.arrayUnion([memory.mood.rawValue])
    ]
    
    // Write memory first, then upsert the date entry
    try await memRef.setData(memData, merge: true)
    try await dateRef.setData(dateData, merge: true)
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
