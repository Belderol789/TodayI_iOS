//
//  MemoryService_Tally.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/11/25.
//

import FirebaseFirestore

extension MemoryService {
  static func incrementDailyMoodTally(for memory: MemoryModel,
                                      db: Firestore = Firestore.firestore()) async throws {
    // Normalize keys/timestamps
    let dayKey = Date().formattedDayKeyLocal()
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
}

extension MemoryService {
  static func fetchMoodTally(for day: Date,
                             db: Firestore = .firestore()) async throws -> [Mood: Int] {
    let dayKey = day.formattedDayKeyLocal() // or dayKeyUTC depending on your setup
    let ref = db.collection("moods").document(dayKey)
    let snap = try await ref.getDocument()
    guard let data = snap.data(),
          let tally = data["tally"] as? [String: Int] else {
      return [:]
    }
    
    var result: [Mood: Int] = [:]
    for (key, val) in tally {
      if let mood = Mood(rawValue: key.capitalized) {
        result[mood] = val
      }
    }
    return result
  }
}
