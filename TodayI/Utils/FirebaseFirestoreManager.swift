//
//  FirebaseFirestoreManager.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/25/25.
//

import FirebaseFirestore
import SwiftData
import FirebaseInstallations

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

      // Only a Global post gets a tokened, world-readable URL. A Personal entry keeps a
      // bare storage path so its photos stay behind the owner-only rule — see
      // FirebaseStorageManager.RemoteMediaRef.
      let isPublic = dto.isPublic

      // Upload images
      for (i, img) in payload.images.enumerated() {
        print("📤 Uploading image \(i + 1)/\(payload.images.count) for userID: \(userID)")
        let ref = try await FirebaseStorageManager.uploadImage(
          img.image,
          userID: userID,
          memoryID: memoryID,
          index: i,
          isPublic: isPublic
        )
        print("✅ Image \(i + 1) uploaded (\(isPublic ? "public" : "protected")): \(ref.stored)")
        remoteImages.append(ref.stored)
      }
      
      // Upload video (if any)
      var videoURLString: String?
      if let videoURL = payload.videoURL {
        print("📤 Uploading video for userID: \(userID), file: \(videoURL.lastPathComponent)")
        let ref = try await FirebaseStorageManager.uploadVideo(
          fileURL: videoURL,
          userID: userID,
          memoryID: memoryID,
          isPublic: isPublic
        )
        videoURLString = ref.stored
        print("✅ Video uploaded (\(isPublic ? "public" : "protected")): \(ref.stored)")
      } else {
        print("ℹ️ No video to upload")
      }

      // Upload audio (if any)
      var audioURLString: String?
      if let audioURL = payload.audioURL {
        print("📤 Uploading audio for userID: \(userID), file: \(audioURL.lastPathComponent)")
        let ref = try await FirebaseStorageManager.uploadAudio(
          fileURL: audioURL,
          userID: userID,
          memoryID: memoryID,
          isPublic: isPublic
        )
        audioURLString = ref.stored
        print("✅ Audio uploaded (\(isPublic ? "public" : "protected")): \(ref.stored)")
      } else {
        print("ℹ️ No audio to upload")
      }

      // Finalize DTO with remote fields
      dto.remoteImagePaths = remoteImages
      dto.videoRemoteURL = videoURLString
      dto.audioRemoteURL = audioURLString
      dto.linkURL = payload.linkString
      print("🟩 Final DTO prepared — images: \(remoteImages.count), video: \(videoURLString ?? "none"), audio: \(audioURLString ?? "none"), link: \(payload.linkString ?? "none")")

      // Update local model with remote fields
      await MainActor.run {
        model.remoteImagePaths = remoteImages
        if let v = videoURLString { model.videoRemoteURL = v }
        if let a = audioURLString { model.audioRemoteURL = a }
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
      // Previously this just logged and the memory silently never synced. Flagging it
      // puts it in the same queue the free-tier backfill drains, so the next launch
      // retries instead of losing it.
      print("❌ Failed in upload task: \(error) — flagged for retry")
      await MainActor.run {
        model.needsCloudBackup = true
        try? context.save()
      }
    }
  }
}
