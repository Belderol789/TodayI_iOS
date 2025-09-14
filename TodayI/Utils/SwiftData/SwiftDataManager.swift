import SwiftData
import Foundation

@MainActor
final class SwiftDataManager {
  private let context: ModelContext
  private let store: EntitlementStore   // check free vs premium
  
  init(context: ModelContext, store: EntitlementStore) {
    self.context = context
    self.store = store
  }
}

extension SwiftDataManager {
  /// Load memories for a given date.
  /// Premium => all; Free => only the latest
  func loadMemories(for date: Date) throws -> [MemoryModel] {
    let cal = Calendar.current
    let key = cal.startOfDay(for: date)
    
    let fetch = FetchDescriptor<MemoryModel>(
      predicate: #Predicate { $0.date == key },
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )
    
    let rows = try context.fetch(fetch)
    return store.isPremium ? rows : (rows.last.map { [$0] } ?? [])
  }
}

extension SwiftDataManager {
  /// Saves a post into SwiftData using DTO for core fields, then patches local media.
  @discardableResult
  func savePostPayload(_ payload: PostPayload,
                       userID: String,
                       username: String,
                       for day: Date = .now) throws -> MemoryModel {
    let now = Date()
    let memoryID = UUID().uuidString
    
    // --- Initial DTO (empty media, will fill later) ---
    var dto = MemoryDTO(
      id: memoryID,
      username: username,
      userID: userID,
      date: day.startOfDayUTC,
      mood: payload.mood.rawValue,
      journalText: payload.text,
      remoteImagePaths: [],
      videoRemoteURL: nil,
      linkURL: payload.linkString,
      isPublic: payload.isPublic,
      createdAt: now,
      updatedAt: now
    )
    
    // --- Upsert into SwiftData immediately ---
    let model = try MemoryModel.upsert(from: dto, in: context)
    
    // Save local image paths (for offline cache)
    if !payload.images.isEmpty {
      model.localImagePaths = try persistImagesToFiles(payload.images, dayKey: day.startOfDayUTC)
    } else {
      model.localImagePaths = []
    }
    
    // Save video local path (for offline cache)
    if let videoURL = payload.videoURL {
      let localPath = try persistVideoToFiles(videoURL, dayKey: day.startOfDayUTC)
      model.videoLocalPath = localPath
    }
    
    // Save link
    if let link = payload.linkString {
      model.linkURL = link
    }
    
    // --- DateModel update (append mood) ---
    let key = Calendar.current.startOfDay(for: day)
    let fetch = FetchDescriptor<DateModel>(predicate: #Predicate { $0.date == key })
    let dateModel = try context.fetch(fetch).first ?? DateModel(date: key)
    
    var moods = dateModel.moods
    moods.append(payload.mood)
    dateModel.moods = moods
    
    if dateModel.modelContext == nil {
      context.insert(dateModel)
    }
    
    try context.save()
    
    // --- Background upload to Firebase Storage + Firestore ---
    Task {
      do {
        print("🟦 Starting upload task for memoryID: \(memoryID)")
        
        var remoteImages: [String] = []
        
        // Upload each image
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
        
        // Upload video if present
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
        
        // Build final DTO with remote paths
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
        
        // Upload to Firestore
        print("📤 Posting memory to Firestore for userID: \(userID)")
        try await MemoryService.postMemory(model)
        print("✅ Post synced to Firestore with remote URLs")
        
      } catch {
        print("❌ Failed in upload task: \(error)")
      }
    }
    
    return model
  }
  
  // MARK: - Helpers
  /// Writes UIImages to app's temporary dir as JPEG and returns file paths.
  private func persistImagesToFiles(_ picked: [PickedImage], dayKey: Date) throws -> [String] {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      .appendingPathComponent("memories", isDirectory: true)
    
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    
    var paths: [String] = []
    for item in picked {
      guard let data = item.image.jpegData(compressionQuality: 0.85) else { continue }
      let name = "\(Int(dayKey.timeIntervalSince1970))-\(UUID().uuidString).jpg"
      let url = dir.appendingPathComponent(name)
      try data.write(to: url, options: .atomic)
      paths.append(url.path)
    }
    return paths
  }
  
  private func persistVideoToFiles(_ originalURL: URL, dayKey: Date) throws -> String {
    // choose a persistent base — Documents or Caches
    let base = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("videos", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    
    let ext = originalURL.pathExtension.isEmpty ? "mp4" : originalURL.pathExtension
    let name = "\(Int(dayKey.timeIntervalSince1970))-\(UUID().uuidString).\(ext)"
    let dest = base.appendingPathComponent(name)
    
    // copy (or move) the file into your sandbox
    if FileManager.default.fileExists(atPath: dest.path) {
      try FileManager.default.removeItem(at: dest)
    }
    try FileManager.default.copyItem(at: originalURL, to: dest)
    return dest.path   // store *path*, not absoluteString
  }
  
}
