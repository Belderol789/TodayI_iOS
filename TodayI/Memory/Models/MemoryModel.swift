import SwiftUI
import SwiftData

@Model
final class MemoryModel {
  @Attribute(.unique) var id: String
  var userID: String                  // <- who owns this memory
  var username: String
  var date: Date
  private(set) var moodRaw: String
  var journalText: String
  
  // media
  var localImagePaths: [String]
  var remoteImagePaths: [String]
  var downloadURLs: [String]
  
  // privacy
  var isPublic: Bool = false          // <- NEW
  
  // timestamps
  var createdAt: Date
  var updatedAt: Date
  
  @Transient
  var mood: Mood {
    get { Mood(rawValue: moodRaw) ?? .neutral }
    set { moodRaw = newValue.rawValue }
  }
  
  init(
    id: String = UUID().uuidString,
    userID: String,
    username: String,
    date: Date,
    mood: Mood,
    journalText: String,
    localImagePaths: [String] = [],
    remoteImagePaths: [String] = [],
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
    self.downloadURLs = downloadURLs
    self.isPublic = isPublic
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

enum MemoryError: Error { case futureDate }

extension MemoryModel {
  var mediaSources: [MediaSource] {
    let locals  = localImagePaths.map { MediaSource.local(path: $0) }
    let remotes = remoteImagePaths.compactMap { URL(string: $0) }.map { MediaSource.remote(url: $0) }
    // For previews you can also stuff SF Symbols into downloadURLs and read them as .symbol:
    let symbols = downloadURLs.map { MediaSource.symbol($0) }
    return locals + remotes + symbols
  }
}
