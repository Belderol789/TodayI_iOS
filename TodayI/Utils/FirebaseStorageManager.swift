import Foundation
import FirebaseStorage
import UIKit

struct FirebaseStorageManager {
  private static let storage = Storage.storage()

  // MARK: - Downscaling
  //
  // Uploads used to be `jpegData(compressionQuality: 0.85)` on the full-resolution
  // UIImage straight from the picker — a 12MP phone photo, so roughly 2.5 MB each, and
  // far larger from a 48MP camera. Every Global feed viewer then downloaded that, which
  // made Storage egress about 90% of the entire Firebase bill.
  //
  // `MediaBlock` renders photos in a 4:5 box at card width — under 1200px even on a 3x
  // display — so nothing above this was ever visible. 1440px keeps headroom for the
  // memory itself being worth something; drop to 1080 if egress needs halving again.
  private static let maxFeedEdge: CGFloat = 1440
  private static let maxProfileEdge: CGFloat = 512
  private static let jpegQuality: CGFloat = 0.8

  /// Aspect-preserving downscale. Returns the original if it is already small enough,
  /// so a screenshot or an already-compressed image isn't re-encoded for nothing.
  private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxEdge else { return image }

    let scale = maxEdge / longest
    let target = CGSize(width: (image.size.width * scale).rounded(),
                        height: (image.size.height * scale).rounded())

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1          // target is already in pixels; don't multiply by screen scale
    format.opaque = true      // JPEG has no alpha anyway, and opaque is cheaper
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
  }

  
  /// Uploads image data and returns the download URL
  static func uploadImage(_ image: UIImage,
                          userID: String,
                          memoryID: String,
                          index: Int) async throws -> URL {
    LoggerManager.instance.logFirebaseCall()
    guard let data = downscaled(image, maxEdge: maxFeedEdge)
      .jpegData(compressionQuality: jpegQuality) else {
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
    
    // Avatars render at ~44pt. 512px is already generous.
    guard let data = downscaled(image, maxEdge: maxProfileEdge)
      .jpegData(compressionQuality: jpegQuality) else {
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

  /// Uploads an audio file and returns the download URL
  static func uploadAudio(fileURL: URL,
                          userID: String,
                          memoryID: String) async throws -> URL {
    LoggerManager.instance.logFirebaseCall()
    let ext = fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension
    let ref = storage.reference()
      .child("users/\(userID)/memories/\(memoryID)/audio.\(ext)")

    let _ = try await ref.putFileAsync(from: fileURL, metadata: nil)
    return try await ref.downloadURL()
  }
}
