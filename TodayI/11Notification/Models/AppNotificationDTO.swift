import FirebaseFirestore

struct AppNotificationDTO: Identifiable, Equatable {
  let id: String
  let type: String            // "like_milestone" | "comment_milestone"
  let postId: String
  let milestone: Int
  let deeplink: String
  let read: Bool
  let createdAt: Date
  
  // Computed display strings
  var title: String {
    switch type {
    case "like_milestone":
      return "Your post has reached \(milestone) likes!"
    case "comment_milestone":
      return milestone == 1
      ? "Your post has received its first comment!"
      : "Your post has received \(milestone) comments!"
    default:
      return "Update"
    }
  }
  var body: String {
    switch type {
    case "like_milestone":    return "Nice! Come see who liked it."
    case "comment_milestone": return "Open TodayI to check the conversation."
    default:                   return ""
    }
  }
  
  init?(doc: DocumentSnapshot) {
    let d = doc.data() ?? [:]
    guard
      let type = d["type"] as? String,
      let postId = d["postId"] as? String,
      let milestone = d["milestone"] as? Int,
      let deeplink = d["deeplink"] as? String,
      let ts = d["createdAt"] as? Timestamp,
      let read = d["read"] as? Bool
    else { return nil }
    self.id = doc.documentID
    self.type = type
    self.postId = postId
    self.milestone = milestone
    self.deeplink = deeplink
    self.read = read
    self.createdAt = ts.dateValue()
  }
}

extension AppNotificationDTO {
  init(
    id: String,
    type: String,
    postId: String,
    milestone: Int,
    deeplink: String,
    read: Bool,
    createdAt: Date
  ) {
    self.id = id
    self.type = type
    self.postId = postId
    self.milestone = milestone
    self.deeplink = deeplink
    self.read = read
    self.createdAt = createdAt
  }
  
  // Handy samples for previews/tests
  static let sampleLike = AppNotificationDTO(
    id: "like_abc_10",
    type: "like_milestone",
    postId: "abc",
    milestone: 10,
    deeplink: "todayi://post/abc",
    read: false,
    createdAt: Date()
  )
  
  static let sampleComment = AppNotificationDTO(
    id: "comment_abc_5",
    type: "comment_milestone",
    postId: "abc",
    milestone: 5,
    deeplink: "todayi://post/abc",
    read: true,
    createdAt: Date().addingTimeInterval(-3600)
  )
}
