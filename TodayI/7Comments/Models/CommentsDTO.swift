// CommentDTO.swift
import FirebaseFirestore

struct CommentDTO: Codable, Identifiable, Equatable {
  let id: String
  let userID: String
  let username: String
  let text: String
  let createdAt: Date
  /// Optional — comments written before this field existed simply have no photo,
  /// and `CommentRow` falls back to the memory's mood icon.
  let photoURL: String?

  init(id: String, userID: String, username: String, text: String, createdAt: Date,
       photoURL: String? = nil) {
    self.id = id
    self.userID = userID
    self.username = username
    self.text = text
    self.createdAt = createdAt
    self.photoURL = photoURL
  }

  init?(doc: DocumentSnapshot) {
    let d = doc.data() ?? [:]
    guard
      let userID = d["userID"] as? String,
      let username = d["username"] as? String,
      let text = d["text"] as? String,
      let ts = d["createdAt"] as? Timestamp
    else { return nil }
    self.id = doc.documentID
    self.userID = userID
    self.username = username
    self.text = text
    self.createdAt = ts.dateValue()
    // Empty string is treated as absent — postMemory-style writes store "" for nil.
    let photo = d["photoURL"] as? String
    self.photoURL = (photo?.isEmpty ?? true) ? nil : photo
  }
}
