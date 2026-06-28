import Foundation

struct MemoryDTO: Codable {
  let id: String
  let username: String
  let userID: String
  let date: Date
  let mood: String
  let journalText: String
  let likes: Int
  
  // media
  var remoteImagePaths: [String]
  var videoRemoteURL: String?
  var audioRemoteURL: String?
  var linkURL: String?
  
  // ✅ New
  var remoteProfilePhotoURL: String?   // Remote URL only
  
  let isPublic: Bool
  let isPremium: Bool?
  let createdAt: Date
  let updatedAt: Date
  
  let authorTZ: String
  let dayKey: String
  
  enum CodingKeys: String, CodingKey {
    case id, username, userID, date, mood, journalText, likes,
         remoteImagePaths, videoRemoteURL, audioRemoteURL, linkURL,
         remoteProfilePhotoURL,
         isPublic, isPremium, createdAt, updatedAt, authorTZ, dayKey
  }
}

extension MemoryDTO {
  init(from model: MemoryModel) {
    self.id = model.id
    self.username = model.username
    self.userID = model.userID
    self.date = model.date
    self.mood = model.moodRaw
    self.journalText = model.journalText
    self.likes = model.likes
    self.remoteImagePaths = model.remoteImagePaths
    self.videoRemoteURL = model.videoRemoteURL
    self.audioRemoteURL = model.audioRemoteURL
    self.linkURL = model.linkURL
    self.remoteProfilePhotoURL = model.remoteProfilePhotoURL   // ✅ only remote version
    self.isPublic = model.isPublic
    self.isPremium = model.isPremium
    self.createdAt = model.createdAt
    self.updatedAt = model.updatedAt
    self.authorTZ = model.authorTZ
    self.dayKey = model.dayKey
  }
  
  init(payload: PostPayload, userID: String, username: String, remoteProfilePhotoURL: String?, day: Date) {
    self.id = UUID().uuidString
    self.username = username
    self.userID = userID
    self.remoteProfilePhotoURL = remoteProfilePhotoURL  // or pass current user's photoURL if available
    self.date = day.startOfDay(in: TimeZone.current)
    self.mood = payload.mood.rawValue
    self.journalText = payload.text
    self.likes = 0
    self.remoteImagePaths = []
    self.videoRemoteURL = nil
    self.audioRemoteURL = nil
    self.linkURL = payload.linkString
    self.isPublic = payload.isPublic
    self.isPremium = payload.isPremium
    self.createdAt = Date()
    self.updatedAt = Date()
    self.authorTZ = TimeZone.current.identifier
    self.dayKey = Date().formattedDayKeyLocal()
  }
  
}
