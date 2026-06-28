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
  
  // MARK: - Device Trial Setup (Transaction)
  static func activateDeviceTrialIfNeeded() async -> Bool {
    do {
      let trialDays = 10
      let deviceTrialID = TrialDeviceID.getOrCreate()
      
      let db = Firestore.firestore()
      let ref = db.collection("trialDevices").document(deviceTrialID)
      
      let result = try await db.runTransaction { transaction, errorPointer -> Any? in
        do {
          let snap = try transaction.getDocument(ref)
          
          if snap.exists {
            return false
          }
          
          transaction.setData([
            "startAt": FieldValue.serverTimestamp(),
            "trialDays": trialDays,
            "trialSource": "first_open"
          ], forDocument: ref)
          
          return true
        } catch {
          // 👇 This is REQUIRED — you cannot throw
          errorPointer?.pointee = error as NSError
          return nil
        }
      }
      
      let didCreate = (result as? Bool) ?? false
      
      if didCreate {
        print("🟢 Activated new \(trialDays)-day trial for device: \(deviceTrialID)")
      } else {
        print("🟡 Trial already exists for device: \(deviceTrialID)")
      }
      
      return didCreate
      
    } catch {
      print("❌ Failed to activate device trial: \(error)")
      return false
    }
  }
  
  // MARK: - Check Trial Status (Server-start-based)
  static func checkDeviceTrialPremium() async -> Bool {
    do {
      let deviceTrialID = TrialDeviceID.getOrCreate()
      
      let db = Firestore.firestore()
      let ref = db.collection("trialDevices").document(deviceTrialID)
      
      let snap = try await ref.getDocument()
      guard let data = snap.data() else {
        print("ℹ️ No trial document found.")
        return false
      }
      
      // Prefer server-based startAt; allow Date fallback for safety
      let startAt: Date
      if let startTS = data["startAt"] as? Timestamp {
        startAt = startTS.dateValue()
      } else if let startDate = data["startAt"] as? Date {
        startAt = startDate
      } else {
        // This can happen immediately after creation because serverTimestamp may not be resolved yet.
        print("⚠️ startAt not available yet.")
        return false
      }
      
      let trialDays = data["trialDays"] as? Int ?? 10
      
      let expiresAt = Calendar.current.date(byAdding: .day, value: trialDays, to: startAt)
      ?? startAt.addingTimeInterval(TimeInterval(60 * 60 * 24 * trialDays))
      
      let now: Date = Date()
      let isPremiumTrial = now < expiresAt
      
      print("""
            🔍 Trial Check
            • now: \(now)
            • start: \(startAt)
            • expires: \(expiresAt)
            • trialDays: \(trialDays)
            • isPremiumTrial: \(isPremiumTrial)
            """)
      
      return isPremiumTrial
      
    } catch {
      print("❌ checkDeviceTrialPremium FAILED: \(error)")
      return false
    }
  }
  
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

      // Upload audio (if any)
      var audioURLString: String?
      if let audioURL = payload.audioURL {
        print("📤 Uploading audio for userID: \(userID), file: \(audioURL.lastPathComponent)")
        let url = try await FirebaseStorageManager.uploadAudio(
          fileURL: audioURL,
          userID: userID,
          memoryID: memoryID
        )
        audioURLString = url.absoluteString
        print("✅ Audio uploaded: \(url.absoluteString)")
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
      print("❌ Failed in upload task: \(error)")
    }
  }
}
