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
  
  // (Optional) Keep this only for SF Symbol placeholders / emoji tags
  var downloadURLs: [String]
  
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
    downloadURLs: [String] = [],
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
    self.downloadURLs = downloadURLs
    self.isPublic = isPublic
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

enum MemoryError: Error { case futureDate }

// MARK: - Helpers
extension MemoryModel {
  /// Prefer local files for rendering; fall back to remote URLs if locals are empty.
  var imageSources: [MediaSource] {
    if !localImagePaths.isEmpty {
      return localImagePaths.map { MediaSource.local(path: $0) }
    } else {
      return remoteImagePaths
        .compactMap(URL.init(string:))
        .map { MediaSource.remote(url: $0) }
    }
  }
}
