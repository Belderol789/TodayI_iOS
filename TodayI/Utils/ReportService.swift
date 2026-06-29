import Foundation
import FirebaseFirestore
import FirebaseAuth

enum ReportReason: String, CaseIterable, Identifiable {
  case inappropriate = "Inappropriate content"
  case harassment    = "Harassment or bullying"
  case spam          = "Spam"
  case hateSpeech    = "Hate speech"
  case other         = "Other"

  var id: String { rawValue }
}

struct ReportService {
  static func report(
    reportedUID: String,
    memoryID: String,
    reason: ReportReason
  ) async throws {
    guard let reporterUID = Auth.auth().currentUser?.uid else { return }
    let db = Firestore.firestore()
    let ref = db.collection("reports").document()
    try await ref.setData([
      "id":          ref.documentID,
      "reporterUID": reporterUID,
      "reportedUID": reportedUID,
      "memoryID":    memoryID,
      "reason":      reason.rawValue,
      "createdAt":   FieldValue.serverTimestamp()
    ])
  }
}
