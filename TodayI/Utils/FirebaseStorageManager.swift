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

  
  // MARK: - Public vs protected media
  //
  // `downloadURL()` returns a URL carrying a `firebaseStorageDownloadTokens` value, and
  // that token **bypasses Storage rules entirely** — which is exactly why the Global feed
  // can show everyone's photos despite an owner-only rule. The cost is that the link is
  // permanent and world-readable by anyone who obtains it.
  //
  // That is fine for a Global post, whose whole purpose is to be seen, and wrong for a
  // Personal entry. So a token is only ever minted for public media; private media keeps
  // a bare storage path and is fetched through the authenticated SDK, where the
  // owner-only rule actually applies.

  /// How a piece of remote media is addressed.
  enum RemoteMediaRef {
    /// A tokened https URL. World-readable by design — public posts only.
    case publicURL(String)
    /// A storage path such as `users/{uid}/memories/{id}/images/0.jpg`.
    /// Rules-protected; needs the SDK and a signed-in owner to read.
    case protectedPath(String)

    /// What gets persisted on the model and the DTO.
    var stored: String {
      switch self {
      case .publicURL(let s), .protectedPath(let s): return s
      }
    }
  }

  /// True when a stored media string is a tokened URL rather than a bare path.
  static func isPublicRef(_ stored: String) -> Bool {
    stored.hasPrefix("http://") || stored.hasPrefix("https://")
  }

  /// Resolves any stored form back to a `StorageReference`.
  static func reference(forStored stored: String) -> StorageReference {
    isPublicRef(stored) || stored.hasPrefix("gs://")
      ? storage.reference(forURL: stored)
      : storage.reference(withPath: stored)
  }

  /// Mints a public, tokened URL for media that is becoming Global.
  static func makePublic(stored: String) async throws -> String {
    guard !isPublicRef(stored) else { return stored }
    let url = try await reference(forStored: stored).downloadURL()
    return url.absoluteString
  }

  /// Revokes the download token and returns the bare path.
  ///
  /// Clearing `firebaseStorageDownloadTokens` invalidates every link already handed out —
  /// this is what makes switching a post back to Personal actually un-share it rather
  /// than just hiding it from the feed.
  static func makeProtected(stored: String) async throws -> String {
    let ref = reference(forStored: stored)
    let meta = StorageMetadata()
    meta.customMetadata = ["firebaseStorageDownloadTokens": ""]
    _ = try? await ref.updateMetadata(meta)
    return ref.fullPath
  }

  /// Uploads image data. Returns a tokened URL for public posts, a bare path otherwise.
  static func uploadImage(_ image: UIImage,
                          userID: String,
                          memoryID: String,
                          index: Int,
                          isPublic: Bool) async throws -> RemoteMediaRef {
    LoggerManager.instance.logFirebaseCall()
    guard let data = downscaled(image, maxEdge: maxFeedEdge)
      .jpegData(compressionQuality: jpegQuality) else {
      throw NSError(domain: "FirebaseStorageManager", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not convert UIImage to JPEG"])
    }
    
    let ref = storage.reference()
      .child("users/\(userID)/memories/\(memoryID)/images/\(index).jpg")
    
    let _ = try await ref.putDataAsync(data, metadata: nil)
    return try await finish(ref, isPublic: isPublic)
  }

  /// Shared tail for every upload: mint a token, or make sure there isn't one.
  ///
  /// The clear is defensive. Whether the Storage backend assigns a token at upload time
  /// or lazily on first `downloadURL()` isn't something we should depend on, and getting
  /// it wrong silently means private media is world-readable. Clearing costs one metadata
  /// write and removes the question.
  private static func finish(_ ref: StorageReference, isPublic: Bool) async throws -> RemoteMediaRef {
    if isPublic {
      return .publicURL(try await ref.downloadURL().absoluteString)
    }
    let meta = StorageMetadata()
    meta.customMetadata = ["firebaseStorageDownloadTokens": ""]
    _ = try? await ref.updateMetadata(meta)
    return .protectedPath(ref.fullPath)
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
                          memoryID: String,
                          isPublic: Bool) async throws -> RemoteMediaRef {
    LoggerManager.instance.logFirebaseCall()
    let ref = storage.reference()
      .child("users/\(userID)/memories/\(memoryID)/video.mp4")

    let _ = try await ref.putFileAsync(from: fileURL, metadata: nil)
    return try await finish(ref, isPublic: isPublic)
  }

  /// Uploads an audio file and returns the download URL
  static func uploadAudio(fileURL: URL,
                          userID: String,
                          memoryID: String,
                          isPublic: Bool) async throws -> RemoteMediaRef {
    LoggerManager.instance.logFirebaseCall()
    let ext = fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension
    let ref = storage.reference()
      .child("users/\(userID)/memories/\(memoryID)/audio.\(ext)")

    let _ = try await ref.putFileAsync(from: fileURL, metadata: nil)
    return try await finish(ref, isPublic: isPublic)
  }
}
