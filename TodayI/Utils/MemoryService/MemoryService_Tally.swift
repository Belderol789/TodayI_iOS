//
//  MemoryService_Tally.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/11/25.
//

import FirebaseFirestore

extension MemoryService {
  /// The `moods/{dayKey}` payload for a post, as a mergeable dictionary.
  ///
  /// The tally lives in a **nested map** rather than a dotted `"tally.happy"` key:
  /// `setData` treats dots as literal characters in a field name (only `updateData`
  /// reads them as paths), and `updateData` would fail on a day nobody has posted
  /// yet. A merged nested map with `increment` creates the day or adds to it, which
  /// is what lets this ride along in `postMemory`'s batch with no read.
  static func moodTallyPayload(for memory: MemoryModel) -> [String: Any] {
    let moodField = memory.mood.rawValue.lowercased()   // "angry", "sad", …
    return [
      "date": Calendar.current.startOfDay(for: memory.date),
      "updatedAt": FieldValue.serverTimestamp(),
      "tally": [moodField: FieldValue.increment(Int64(1))]
    ]
  }

  /// Standalone version, kept for any caller that isn't already batching.
  static func incrementDailyMoodTally(for memory: MemoryModel,
                                      db: Firestore = Firestore.firestore()) async throws {
    try await db.collection("moods").document(memory.dayKey)
      .setData(moodTallyPayload(for: memory), merge: true)
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
