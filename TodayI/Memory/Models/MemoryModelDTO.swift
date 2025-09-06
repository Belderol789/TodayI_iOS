import Foundation
import SwiftData

struct MemoryDTO: Codable {
  let id: String
  let date: Date         // UTC midnight for that day
  let mood: String       // Mood.rawValue
  let journalText: String
  let remoteImagePaths: [String]
  let downloadURLs: [String]
  let createdAt: Date
  let updatedAt: Date
}

// SwiftData -> Firestore
extension MemoryDTO {
  init(from model: MemoryModel) {
    self.id = model.id
    self.date = model.date
    self.mood = model.moodRaw
    self.journalText = model.journalText
    self.remoteImagePaths = model.remoteImagePaths
    self.downloadURLs = model.downloadURLs
    self.createdAt = model.createdAt
    self.updatedAt = model.updatedAt
  }
}

// Firestore -> SwiftData
extension MemoryModel {
  static func fromDTO(_ dto: MemoryDTO, in context: ModelContext) -> MemoryModel {
    let m = MemoryModel(
      id: dto.id,
      username: "Kembel",
      date: dto.date,
      mood: Mood(rawValue: dto.mood) ?? .neutral,
      journalText: dto.journalText,
      localImagePaths: [],                 // you’ll fill these after downloads
      remoteImagePaths: dto.remoteImagePaths,
      downloadURLs: dto.downloadURLs,
      createdAt: dto.createdAt,
      updatedAt: dto.updatedAt
    )
    context.insert(m)
    return m
  }
}
