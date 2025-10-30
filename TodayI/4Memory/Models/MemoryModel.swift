import SwiftUI
import SwiftData

@Model
final class MemoryModel {
  // Identity
  @Attribute(.unique) var id: String
  var userID: String
  var username: String
  
  // NEW: Profile Photo (Optional)
  var remoteProfilePhotoURL: String?     // ✅ URL from Firestore/DTO
  var localProfilePhotoPath: String?     // ✅ Optional cached image path
  
  var date: Date
  var authorTZ: String
  var dayKey: String
  private(set) var moodRaw: String
  
  var journalText: String
  var likes: Int
  
  // Media
  var localImageNames: [String]
  var remoteImagePaths: [String]
  var videoLocalPath: String?
  var videoRemoteURL: String?
  var linkURL: String?
  
  // Privacy / Premium
  var isPublic: Bool = false
  var isPremium: Bool
  
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
    remoteProfilePhotoURL: String? = nil,
    localProfilePhotoPath: String? = nil,
    date: Date,
    mood: Mood,
    journalText: String,
    likes: Int,
    localImageNames: [String] = [],
    remoteImagePaths: [String] = [],
    videoLocalPath: String? = nil,
    videoRemoteURL: String? = nil,
    linkURL: String? = nil,
    isPublic: Bool = false,
    isPremium: Bool,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.userID = userID
    self.username = username
    self.remoteProfilePhotoURL = remoteProfilePhotoURL
    self.localProfilePhotoPath = localProfilePhotoPath
    self.date = Calendar.current.startOfDay(for: date)
    self.moodRaw = mood.rawValue
    self.journalText = journalText
    self.likes = likes
    self.localImageNames = localImageNames
    self.remoteImagePaths = remoteImagePaths
    self.videoLocalPath = videoLocalPath
    self.videoRemoteURL = videoRemoteURL
    self.linkURL = linkURL
    self.isPublic = isPublic
    self.isPremium = isPremium
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.authorTZ = TimeZone.current.identifier
    self.dayKey = Date().formattedDayKeyLocal()
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
      m.date = dto.date
      m.remoteProfilePhotoURL = dto.remoteProfilePhotoURL
      m.mood = Mood(rawValue: dto.mood) ?? .neutral
      m.journalText = dto.journalText
      m.remoteImagePaths = dto.remoteImagePaths
      m.videoRemoteURL = dto.videoRemoteURL    // 👈
      m.linkURL = dto.linkURL                  // 👈
      m.isPublic = dto.isPublic
      m.updatedAt = dto.updatedAt
      m.authorTZ = dto.authorTZ
      m.dayKey = dto.dayKey
      return m
    } else {
      let m = MemoryModel(
        id: dto.id,
        userID: dto.userID,
        username: dto.username,
        remoteProfilePhotoURL: dto.remoteProfilePhotoURL,
        date: dto.date,
        mood: Mood(rawValue: dto.mood) ?? .neutral,
        journalText: dto.journalText,
        likes: dto.likes,
        localImageNames: [],
        remoteImagePaths: dto.remoteImagePaths,
        videoLocalPath: nil,                    // 👈 stays nil from DTO
        videoRemoteURL: dto.videoRemoteURL,     // 👈
        linkURL: dto.linkURL,                   // 👈
        isPublic: dto.isPublic,
        isPremium: dto.isPremium,
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
  
  /// ✅ Cleaned helper: Choose local profile photo first, else remote
  @Transient
  var authorProfilePhotoURL: URL? {
    if let local = localProfilePhotoPath {
      return URL(fileURLWithPath: local)
    }
    if let remote = remoteProfilePhotoURL {
      return URL(string: remote)
    }
    return nil
  }
  
  /// Prefer local memory images; fallback to remotes
  var imageSources: [MediaSource] {
    let validLocal = localImagePaths.filter {
      FileManager.default.fileExists(atPath: $0)
    }
    if !validLocal.isEmpty {
      return validLocal.map { .localImage(path: $0) }
    }
    return remoteImagePaths.compactMap(URL.init(string:)).map { .remoteImage(url: $0) }
  }
  
  /// Prefer local video; fallback to remote
  @Transient
  var videoSource: MediaSource? {
    if let path = videoLocalPath, FileManager.default.fileExists(atPath: path) {
      return .localVideo(path: path)
    }
    if let s = videoRemoteURL, let u = URL(string: s) {
      return .remoteVideo(url: u)
    }
    return nil
  }
  
  /// Generates resolved local filepaths for images
  @Transient
  var localImagePaths: [String] {
    localImageNames.compactMap { filename in
      FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("memories", isDirectory: true)
        .appendingPathComponent(filename)
        .path
    }
  }
}


