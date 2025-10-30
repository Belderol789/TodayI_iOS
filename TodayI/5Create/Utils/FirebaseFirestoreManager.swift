//
//  FirebaseFirestoreManager.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/25/25.
//

import FirebaseFirestore
import SwiftData

struct FirebaseFirestoreManager {
  // MARK: - Firebase sync (private)
  
  /// Uploads media to Firebase Storage, updates the local model with remote URLs,
  /// and posts to Firestore. Runs on a background Task from the caller.
  static func uploadToFirebase(context: ModelContext,
                               dto: MemoryDTO,
                               payload: PostPayload,
                               model: MemoryModel,
                               userID: String,
                               dayStartLocal: Date) async {
    var dto = dto // we’ll mutate remote fields
    let memoryID = dto.id
    
    do {
      print("🟦 Starting upload task for memoryID: \(memoryID)")
      
      var remoteImages: [String] = []
      
      // Upload images
      for (i, img) in payload.images.enumerated() {
        print("📤 Uploading image \(i + 1)/\(payload.images.count) for userID: \(userID)")
        let url = try await FirebaseStorageManager.uploadImage(
          img.image,
          userID: userID,
          memoryID: memoryID,
          index: i
        )
        print("✅ Image \(i + 1) uploaded: \(url.absoluteString)")
        remoteImages.append(url.absoluteString)
      }
      
      // Upload video (if any)
      var videoURLString: String?
      if let videoURL = payload.videoURL {
        print("📤 Uploading video for userID: \(userID), file: \(videoURL.lastPathComponent)")
        let url = try await FirebaseStorageManager.uploadVideo(
          fileURL: videoURL,
          userID: userID,
          memoryID: memoryID
        )
        videoURLString = url.absoluteString
        print("✅ Video uploaded: \(url.absoluteString)")
      } else {
        print("ℹ️ No video to upload")
      }
      
      // Finalize DTO with remote fields
      dto.remoteImagePaths = remoteImages
      dto.videoRemoteURL = videoURLString
      dto.linkURL = payload.linkString
      print("🟩 Final DTO prepared with \(remoteImages.count) images, video: \(videoURLString ?? "none"), link: \(payload.linkString ?? "none")")
      
      // Update local model with remote fields
      await MainActor.run {
        model.remoteImagePaths = remoteImages
        if let v = videoURLString { model.videoRemoteURL = v }
        if let l = payload.linkString { model.linkURL = l }
        model.updatedAt = Date()
        do {
          try context.save()
          print("💾 Local SwiftData updated successfully")
        } catch {
          print("⚠️ Failed to save SwiftData update: \(error)")
        }
      }
      
      // Push to Firestore
      print("📤 Posting memory to Firestore for userID: \(userID)")
      try await MemoryService.postMemory(model)
      print("✅ Post synced to Firestore with remote URLs")
      
    } catch {
      print("❌ Failed in upload task: \(error)")
    }
  }
}
