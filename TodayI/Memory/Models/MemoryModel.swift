import SwiftUI
import SwiftData

@Model
final class MemoryModel {
  // Identity
  @Attribute(.unique) var id: String
  var username: String
  var userID: String
  
  // Core fields
  var date: Date                 // normalized (start-of-day)
  private(set) var moodRaw: String
  var journalText: String
  
  // Image references (local disk or Firebase Storage paths / URLs)
  var localImagePaths: [String]  // e.g. file paths in Documents/Cache
  var remoteImagePaths: [String] // e.g. "users/{uid}/memories/{id}/img_0.jpg"
  var downloadURLs: [String]     // optional https URLs (if you fetch them)
  
  // Metadata
  var createdAt: Date
  var updatedAt: Date
  
  // Computed mood
  @Transient
  var mood: Mood {
    get { Mood(rawValue: moodRaw) ?? .neutral }
    set { moodRaw = newValue.rawValue }
  }
  
  // Designated init (use factory below in production code)
  init(
    id: String = UUID().uuidString,
    username: String,
    date: Date,
    mood: Mood,
    journalText: String,
    localImagePaths: [String] = [],
    remoteImagePaths: [String] = [],
    downloadURLs: [String] = [],
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.username = username
    self.date = Calendar.current.startOfDay(for: date)
    self.moodRaw = mood.rawValue
    self.journalText = journalText
    self.localImagePaths = localImagePaths
    self.remoteImagePaths = remoteImagePaths
    self.downloadURLs = downloadURLs
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

enum MemoryError: Error { case futureDate }

extension MemoryModel {
  static func make(
    username: String,
    date: Date,
    mood: Mood,
    journalText: String,
    localImagePaths: [String] = []
  ) throws -> MemoryModel {
    let cal = Calendar.current
    let day = cal.startOfDay(for: date)
    let today = cal.startOfDay(for: Date())
    guard day <= today else { throw MemoryError.futureDate }
    
    return MemoryModel(
      username: username,
      date: day,
      mood: mood,
      journalText: journalText,
      localImagePaths: localImagePaths
    )
  }
}

extension MemoryModel {
  var mediaSources: [MediaSource] {
    let locals  = localImagePaths.map { MediaSource.local(path: $0) }
    let remotes = remoteImagePaths.compactMap { URL(string: $0) }.map { MediaSource.remote(url: $0) }
    // For previews you can also stuff SF Symbols into downloadURLs and read them as .symbol:
    let symbols = downloadURLs.map { MediaSource.symbol($0) }
    return locals + remotes + symbols
  }
}
