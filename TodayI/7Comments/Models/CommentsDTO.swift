// CommentDTO.swift
import FirebaseFirestore

struct CommentDTO: Codable, Identifiable, Equatable {
  let id: String
  let userID: String
  let username: String
  let text: String
  let createdAt: Date
  
  init(id: String, userID: String, username: String, text: String, createdAt: Date) {
    self.id = id
    self.userID = userID
    self.username = username
    self.text = text
    self.createdAt = createdAt
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
  }
}
