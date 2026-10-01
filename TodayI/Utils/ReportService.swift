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
  /// Files a report on a post, or on one comment under it when `commentID` is given.
  ///
  /// A comment report carries the comment's text as it stood. Comments can be deleted by
  /// their author, and a report pointing at a comment that no longer exists would leave
  /// nothing to review; the `reports` rule doesn't restrict fields, so no rule change.
  static func report(
    reportedUID: String,
    memoryID: String,
    reason: ReportReason,
    commentID: String? = nil,
    commentText: String? = nil
  ) async throws {
    guard let reporterUID = Auth.auth().currentUser?.uid else { return }
    LoggerManager.instance.logFirebaseCall()
    let db = Firestore.firestore()
    let ref = db.collection("reports").document()
    var data: [String: Any] = [
      "id":          ref.documentID,
      "reporterUID": reporterUID,
      "reportedUID": reportedUID,
      "memoryID":    memoryID,
      "reason":      reason.rawValue,
      "createdAt":   FieldValue.serverTimestamp()
    ]
    if let commentID { data["commentID"] = commentID }
    if let commentText { data["commentText"] = commentText }
    try await ref.setData(data)
  }
}
