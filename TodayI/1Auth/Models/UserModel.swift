import SwiftData
import Foundation

@Model
final class UserModel {
  @Attribute(.unique) var id: String          // Firebase uid (stable)
  var username: String
  var email: String?
  var isAnonymous: Bool
  var photoURL: String?
  var localPhotoPath: String? // ✅ NEW: Local cached version
  var createdAt: Date
  var updatedAt: Date
  
  init(id: String,
       username: String,
       email: String? = nil,
       isAnonymous: Bool,
       photoURL: String? = nil,
       createdAt: Date = .now,
       updatedAt: Date = .now) {
    self.id = id
    self.username = username
    self.email = email
    self.isAnonymous = isAnonymous
    self.photoURL = photoURL
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

extension UserModel {
  @Transient
  var resolvedPhotoURL: URL? {
    if let local = localPhotoPath {
      return URL(fileURLWithPath: local)
    }
    if let remote = photoURL {
      return URL(string: remote)
    }
    return nil
  }
}
