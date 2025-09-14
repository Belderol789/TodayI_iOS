import SwiftUI
import SwiftData

@Model
final class MemoryModel {
  // Identity
  @Attribute(.unique) var id: String
  var userID: String                  // who owns this memory
  var username: String
  var date: Date
  private(set) var moodRaw: String
  var journalText: String
  
  // Media (separated cleanly)
  var localImagePaths: [String]       // device file paths before upload
  var remoteImagePaths: [String]      // Firebase Storage URLs after upload
  var videoLocalPath: String?         // device file path for trimmed video
  var videoRemoteURL: String?         // Firebase Storage URL for video
  var linkURL: String?                // external website link
  
  // Privacy
  var isPublic: Bool = false
  
  // Timestamps
  var createdAt: Date
  var updatedAt: Date
  
  // Derived mood property
  @Transient
  var mood: Mood {
    get { Mood(rawValue: moodRaw) ?? .neutral }
    set { moodRaw = newValue.rawValue }
  }
  
  // Init
  init(
    id: String = UUID().uuidString,
    userID: String,
    username: String,
    date: Date,
    mood: Mood,
    journalText: String,
    localImagePaths: [String] = [],
    remoteImagePaths: [String] = [],
    videoLocalPath: String? = nil,
    videoRemoteURL: String? = nil,
    linkURL: String? = nil,
    isPublic: Bool = false,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.userID = userID
    self.username = username
    self.date = Calendar.current.startOfDay(for: date)
    self.moodRaw = mood.rawValue
    self.journalText = journalText
    self.localImagePaths = localImagePaths
    self.remoteImagePaths = remoteImagePaths
    self.videoLocalPath = videoLocalPath
    self.videoRemoteURL = videoRemoteURL
    self.linkURL = linkURL
    self.isPublic = isPublic
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

enum MemoryError: Error { case futureDate }

// MARK: - MemoryDTO
extension MemoryModel {
  @discardableResult
  static func upsert(from dto: MemoryDTO, in context: ModelContext) throws -> MemoryModel {
    var fetch = FetchDescriptor<MemoryModel>(predicate: #Predicate { $0.id == dto.id })
    fetch.fetchLimit = 1
    let existing: MemoryModel? = try context.fetch(fetch).first
    
    if let m = existing {
      m.username = dto.username
      m.userID = dto.userID
      m.date = dto.date.startOfDayUTC
      m.mood = Mood(rawValue: dto.mood) ?? .neutral
      m.journalText = dto.journalText
      m.remoteImagePaths = dto.remoteImagePaths
      m.videoRemoteURL = dto.videoRemoteURL    // 👈
      m.linkURL = dto.linkURL                  // 👈
      m.isPublic = dto.isPublic
      m.updatedAt = dto.updatedAt
      return m
    } else {
      let m = MemoryModel(
        id: dto.id,
        userID: dto.userID,
        username: dto.username,
        date: dto.date.startOfDayUTC,
        mood: Mood(rawValue: dto.mood) ?? .neutral,
        journalText: dto.journalText,
        localImagePaths: [],
        remoteImagePaths: dto.remoteImagePaths,
        videoLocalPath: nil,                    // 👈 stays nil from DTO
        videoRemoteURL: dto.videoRemoteURL,     // 👈
        linkURL: dto.linkURL,                   // 👈
        isPublic: dto.isPublic,
        createdAt: dto.createdAt,
        updatedAt: dto.updatedAt
      )
      context.insert(m)
      return m
    }
  }
}

// MARK: - Helpers
extension MemoryModel {
  // Prefer local images; fall back to remotes
  var imageSources: [MediaSource] {
    if !localImagePaths.isEmpty {
      return localImagePaths.map { .localImage(path: $0) }
    } else {
      return remoteImagePaths
        .compactMap(URL.init(string:))
        .map { .remoteImage(url: $0) }
    }
  }
  
  // Prefer local video; fall back to remote
  var videoSource: MediaSource? {
    if let path = videoLocalPath, FileManager.default.fileExists(atPath: path) {
      return .localVideo(path: path)
    }
    if let s = videoRemoteURL, let u = URL(string: s) {
      return .remoteVideo(url: u)
    }
    return nil
  }
}
