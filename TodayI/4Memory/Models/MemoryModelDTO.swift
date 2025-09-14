import Foundation
import SwiftData

// MARK: - DTO

struct MemoryDTO: Codable {
  let id: String
  let username: String
  let userID: String
  /// UTC midnight for that calendar day
  let date: Date
  let mood: String                 // Mood.rawValue
  let journalText: String
  var remoteImagePaths: [String]
  var downloadURLs: [String]
  let isPublic: Bool               // ← include privacy
  let createdAt: Date
  let updatedAt: Date
  
  enum CodingKeys: String, CodingKey {
    case id, username, userID, date, mood, journalText,
         remoteImagePaths, downloadURLs, isPublic, createdAt, updatedAt
  }
}

// MARK: - SwiftData -> DTO

extension MemoryDTO {
  init(from model: MemoryModel) {
    self.id = model.id
    self.username = model.username
    self.userID = model.userID
    self.date = model.date.startOfDayUTC               // normalize to UTC
    self.mood = model.moodRaw
    self.journalText = model.journalText
    self.remoteImagePaths = model.remoteImagePaths
    self.downloadURLs = model.downloadURLs
    self.isPublic = model.isPublic
    self.createdAt = model.createdAt
    self.updatedAt = model.updatedAt
  }
}

// MARK: - DTO -> SwiftData (upsert)

extension MemoryModel {
  /// Upsert: fetch by id; update or insert.
  @discardableResult
  static func upsert(from dto: MemoryDTO, in context: ModelContext) throws -> MemoryModel {
    // Build descriptor
    var fetch = FetchDescriptor<MemoryModel>(
      predicate: #Predicate { $0.id == dto.id }
    )
    fetch.fetchLimit = 1
    
    // Fetch existing (explicit type helps inference)
    let existing: MemoryModel? = try context.fetch(fetch).first
    
    if let m = existing {
      // update
      m.username = dto.username
      m.userID = dto.userID
      m.date = dto.date.startOfDayUTC
      m.mood = Mood(rawValue: dto.mood) ?? .neutral
      m.journalText = dto.journalText
      m.remoteImagePaths = dto.remoteImagePaths
      m.downloadURLs = dto.downloadURLs
      m.isPublic = dto.isPublic
      m.updatedAt = dto.updatedAt
      return m
    } else {
      // insert
      let m = MemoryModel(
        id: dto.id,
        userID: dto.userID,
        username: dto.username,
        date: dto.date.startOfDayUTC,
        mood: Mood(rawValue: dto.mood) ?? .neutral,
        journalText: dto.journalText,
        localImagePaths: [],
        remoteImagePaths: dto.remoteImagePaths,
        downloadURLs: dto.downloadURLs,
        isPublic: dto.isPublic,
        createdAt: dto.createdAt,
        updatedAt: dto.updatedAt
      )
      context.insert(m)
      return m
    }
  }
}
