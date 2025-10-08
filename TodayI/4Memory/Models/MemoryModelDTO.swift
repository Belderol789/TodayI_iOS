import Foundation

struct MemoryDTO: Codable {
  let id: String
  let username: String
  let userID: String
  let date: Date
  let mood: String
  let journalText: String
  
  // media
  var remoteImagePaths: [String]
  var videoRemoteURL: String?      // 👈 NEW
  var linkURL: String?             // 👈 NEW
  
  let isPublic: Bool
  let isPremium: Bool
  let createdAt: Date
  let updatedAt: Date
  
  let authorTZ: String
  let dayKeyLocal: String
  let dayKeyUTC: String?      // optional
  
  enum CodingKeys: String, CodingKey {
    case id, username, userID, date, mood, journalText,
         remoteImagePaths, videoRemoteURL, linkURL,
         isPublic, isPremium, createdAt, updatedAt, authorTZ, dayKeyLocal,
         dayKeyUTC
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
    self.remoteImagePaths = model.remoteImagePaths
    self.videoRemoteURL = model.videoRemoteURL       // 👈
    self.linkURL = model.linkURL                     // 👈
    self.isPublic = model.isPublic
    self.isPremium = model.isPremium
    self.createdAt = model.createdAt
    self.updatedAt = model.updatedAt
    
    authorTZ = model.authorTZ
    dayKeyLocal = model.dayKeyLocal
    dayKeyUTC = model.dayKeyUTC
  }
  
  init(payload: PostPayload, userID: String, username: String, day: Date) {
    self.id = UUID().uuidString
    self.username = username
    self.userID = userID
    self.date = day.startOfDay(in: TimeZone.current)
    self.mood = payload.mood.rawValue
    self.journalText = payload.text
    self.remoteImagePaths = []
    self.videoRemoteURL = nil
    self.linkURL = payload.linkString
    self.isPublic = payload.isPublic
    self.isPremium = payload.isPremium
    self.createdAt = Date()
    self.updatedAt = Date()
    self.authorTZ = TimeZone.current.identifier
    self.dayKeyLocal = day.dayKeyLocal(in: TimeZone.current)
    self.dayKeyUTC = Date().dayKeyUTC
  }
  
}
