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
  
  // Trial methods
  // MARK: - Device Trial Setup
  static func activateDeviceTrialIfNeeded() async -> Bool {
    do {
      // 1. Get unique device installation ID
      let installID = try await Installations.installations().installationID()
      
      let db = Firestore.firestore()
      let ref = db.collection("trialDevices").document(installID)
      
      // 2. Check if trial already exists
      let snap = try await ref.getDocument()
      if snap.exists {
        print("🟡 Trial already exists for device: \(installID)")
        return false  // no activation happened
      }
      
      // 3. Create new trial doc using server timestamp
      let expiresAt = Calendar.current.date(
        byAdding: .day,
        value: 30,
        to: Date()
      )
      
      try await ref.setData([
        "startAt": FieldValue.serverTimestamp(),
        "expiresAt": expiresAt ?? Date().addingTimeInterval(60 * 60 * 24 * 30),
        "trialSource": "first_open",
      ])
      
      print("🟢 Activated new 30-day trial for device: \(installID)")
      return true
      
    } catch {
      print("❌ Failed to activate device trial: \(error)")
      return false
    }
  }
  
  
  // MARK: - Check Trial Status
  static func checkDeviceTrialPremium() async -> Bool {
    do {
      let installID = try await Installations.installations().installationID()
      let db = Firestore.firestore()
      let ref = db.collection("trialDevices").document(installID)
      
      // 1. Load document
      let snap = try await ref.getDocument()
      guard let data = snap.data() else {
        print("ℹ️ No trial document found.")
        return false
      }
      
      // 2. Read expiration
      guard let expiresTS = data["expiresAt"] as? Timestamp else {
        print("⚠️ No expiresAt found in trial doc.")
        return false
      }
      
      let expiresAt = expiresTS.dateValue()
      let now = Date()
      
      // 3. Compare server-based expiration
      let isPremiumTrial = now < expiresAt
      
      print("""
                  🔍 Trial Check
                  • now: \(now)
                  • expires: \(expiresAt)
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
