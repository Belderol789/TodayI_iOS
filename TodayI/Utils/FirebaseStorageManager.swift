import Foundation
import FirebaseStorage
import UIKit

struct FirebaseStorageManager {
  private static let storage = Storage.storage()
  
  /// Uploads image data and returns the download URL
  static func uploadImage(_ image: UIImage,
                          userID: String,
                          memoryID: String,
                          index: Int) async throws -> URL {
    LoggerManager.instance.logFirebaseCall()
    guard let data = image.jpegData(compressionQuality: 0.85) else {
      throw NSError(domain: "FirebaseStorageManager", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not convert UIImage to JPEG"])
    }
    
    let ref = storage.reference()
      .child("users/\(userID)/memories/\(memoryID)/images/\(index).jpg")
    
    let _ = try await ref.putDataAsync(data, metadata: nil)
    return try await ref.downloadURL()
  }
  
  static func uploadProfilePhoto(_ image: UIImage, userID: String) async throws -> URL {
    LoggerManager.instance.logFirebaseCall()
    
    guard let data = image.jpegData(compressionQuality: 0.85) else {
      throw NSError(
        domain: "FirebaseStorageManager",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG."]
      )
    }
    
    let ref = storage.reference()
      .child("users/\(userID)/profile/profile.jpg")
    
    _ = try await ref.putDataAsync(data, metadata: nil)
    return try await ref.downloadURL()
  }
  
  /// Uploads a video file and returns the download URL
  static func uploadVideo(fileURL: URL,
                          userID: String,
                          memoryID: String) async throws -> URL {
    LoggerManager.instance.logFirebaseCall()
    let ref = storage.reference()
      .child("users/\(userID)/memories/\(memoryID)/video.mp4")
    
    let _ = try await ref.putFileAsync(from: fileURL, metadata: nil)
    return try await ref.downloadURL()
  }
}
