import Foundation

struct MemoryDTO: Codable {
  let id: String
  let username: String
  let userID: String
  let date: Date
  let mood: String
  let journalText: String
  let likes: Int
  var likedBy: [String]

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
    case id, username, userID, date, mood, journalText, likes, likedBy,
         remoteImagePaths, videoRemoteURL, audioRemoteURL, linkURL,
         remoteProfilePhotoURL,
         isPublic, isPremium, createdAt, updatedAt, authorTZ, dayKey
  }
}

// MARK: - Decoding
extension MemoryDTO {
  /// Hand-written so a missing field defaults instead of failing the whole document.
  /// `postMemory` did not write `likedBy` until after the like system shipped, so every
  /// memory created before that has no such key — synthesized decoding threw
  /// `keyNotFound` on all of them and `fetchMemories` silently returned an empty list.
  /// Defaults here must stay in sync with `GlobalFeedService.decodeDTOManually`.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id                    = try c.decode(String.self, forKey: .id)
    username              = try c.decode(String.self, forKey: .username)
    userID                = try c.decode(String.self, forKey: .userID)
    date                  = try c.decode(Date.self, forKey: .date)
    mood                  = try c.decode(String.self, forKey: .mood)
    journalText           = try c.decode(String.self, forKey: .journalText)
    isPublic              = try c.decode(Bool.self, forKey: .isPublic)
    createdAt             = try c.decode(Date.self, forKey: .createdAt)
    updatedAt             = try c.decode(Date.self, forKey: .updatedAt)

    likes                 = try c.decodeIfPresent(Int.self, forKey: .likes) ?? 0
    likedBy               = try c.decodeIfPresent([String].self, forKey: .likedBy) ?? []
    remoteImagePaths      = try c.decodeIfPresent([String].self, forKey: .remoteImagePaths) ?? []
    videoRemoteURL        = try c.decodeIfPresent(String.self, forKey: .videoRemoteURL)
    audioRemoteURL        = try c.decodeIfPresent(String.self, forKey: .audioRemoteURL)
    linkURL               = try c.decodeIfPresent(String.self, forKey: .linkURL)
    remoteProfilePhotoURL = try c.decodeIfPresent(String.self, forKey: .remoteProfilePhotoURL)
    isPremium             = try c.decodeIfPresent(Bool.self, forKey: .isPremium)

    authorTZ = try c.decodeIfPresent(String.self, forKey: .authorTZ) ?? TimeZone.current.identifier
    dayKey   = try c.decodeIfPresent(String.self, forKey: .dayKey) ?? date.formattedDayKeyLocal()
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
    self.likedBy = model.likedBy
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
    self.likedBy = []
    self.remoteImagePaths = []
    self.videoRemoteURL = nil
    self.audioRemoteURL = nil
    self.linkURL = payload.linkString
    self.isPublic = payload.isPublic
    self.isPremium = payload.isPremium
    self.createdAt = Date()
    self.updatedAt = Date()
    self.authorTZ = TimeZone.current.identifier
    // From `day`, not `Date()` — see the note in `MemoryModel.init`.
    self.dayKey = day.formattedDayKeyLocal()
  }
  
}
