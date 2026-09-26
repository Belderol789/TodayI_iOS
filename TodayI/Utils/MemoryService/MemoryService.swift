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
    
    // The memory's own key — derived from its date at init, not recomputed from `Date()`.
    // Recomputing here meant a post written just after midnight, or for any past day,
    // landed under the wrong dayKey and under the wrong `dates/{dayKey}` document.
    let dayKey = memory.dayKey
    let dateRef = userDoc.collection("dates").document(dayKey)
    
    // --- Memory payload (omit local-only paths) ---
    let memData: [String: Any] = [
      "id": memory.id,
      "userID": memory.userID,
      "username": memory.username,
      "remoteProfilePhotoURL": memory.remoteProfilePhotoURL ?? "",
      "date": Timestamp(date: memory.date),    // ✅ FIXED
      "dayKey": dayKey,
      "authorTZ": memory.authorTZ,
      "mood": memory.mood.rawValue,
      "journalText": memory.journalText,
      "likes": memory.likes,
      "likedBy": memory.likedBy,          // ✅ must be written — toggleLike and the
                                          // Firestore rule both read this field back
      "remoteImagePaths": memory.remoteImagePaths,
      "videoRemoteURL": memory.videoRemoteURL as Any,
      "audioRemoteURL": memory.audioRemoteURL as Any,
      "linkURL": memory.linkURL as Any,
      "isPublic": memory.isPublic,
      "isPremium": memory.isPremium,          // ✅ SAFETY ADD
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp()
    ]
    
    print("📄 Attempting to write memData:", memData)
    
    // --- DateModel payload (server-merge, add mood) ---
    let startOfDay = Calendar.current.startOfDay(for: memory.date)
    let dateData: [String: Any] = [
      "date": startOfDay,                       // Timestamp
      "moodRaws": FieldValue.arrayUnion([memory.mood.rawValue]),
      "updatedAt": FieldValue.serverTimestamp()
    ]
    
    MemoryService.assertMemoryPayload(memory)

    // One batch instead of four sequential round trips (memory → date → mood tally
    // transaction → comments hub). Also removes the tally's read: `increment` inside
    // a merged nested map creates the document when absent, so the transaction that
    // existed only to check `snap.exists` isn't needed. Being atomic is a bonus —
    // a post can no longer half-land as a memory with no matching date entry.
    let batch = db.batch()
    batch.setData(memData, forDocument: memRef, merge: true)
    batch.setData(dateData, forDocument: dateRef, merge: true)
    batch.setData(moodTallyPayload(for: memory),
                  forDocument: db.collection("moods").document(dayKey),
                  merge: true)
    batch.setData(commentsHubPayload(memoryID: memory.id,
                                     ownerID: memory.userID,
                                     isPublic: memory.isPublic,
                                     dayKey: dayKey),
                  forDocument: db.collection("comments").document(memory.id),
                  merge: true)
    try await batch.commit()
  }
  
  private static func assertMemoryPayload(_ m: MemoryModel) {
    func isHttps(_ s: String?) -> Bool { s?.hasPrefix("http://") == true || s?.hasPrefix("https://") == true }
    let usernameOK = !m.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && m.username.count <= 64
    let moodOK     = true // rules now accept String OR Int; rawValue ok
    // Personal entries store a bare storage path instead of a tokened URL, so "is it
    // https" is no longer the right question — either form is valid.
    let imgsOK     = m.remoteImagePaths.count <= 12
    let linkOK     = m.linkURL == nil || isHttps(m.linkURL)
    let videoOK    = m.videoRemoteURL == nil || !m.videoRemoteURL!.isEmpty
    let audioOK    = m.audioRemoteURL == nil || !m.audioRemoteURL!.isEmpty

    print("Rules preflight — usernameOK:", usernameOK,
          "moodOK:", moodOK, "imgsOK:", imgsOK, "linkOK:", linkOK,
          "videoOK:", videoOK, "audioOK:", audioOK)
  }
}


