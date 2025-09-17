import Foundation
import SwiftData
import FirebaseFirestore

struct DateDTO: Codable {
  let dayKeyLocal: String   // "yyyy-MM-dd" in author’s tz
  let date: Date            // canonical startOfDay
  let moodRaws: [String]
}

extension DateDTO {
  init?(doc: DocumentSnapshot) {
    guard let data = doc.data(),
          let ts = data["date"] as? Timestamp else { return nil }
    self.date = ts.dateValue()
    self.dayKeyLocal = data["dayKeyLocal"] as? String ?? ""
    self.moodRaws = data["moodRaws"] as? [String] ?? []
  }
}
