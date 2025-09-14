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
    
    let dto = MemoryDTO(
      id: memoryID,
      username: username,
      userID: userID,
      date: day.startOfDayUTC,
      mood: payload.mood.rawValue,
      journalText: payload.text,
      remoteImagePaths: [],                 // filled later
      downloadURLs: payload.linkString.map { [$0] } ?? [],
      isPublic: payload.isPublic,
      createdAt: now,
      updatedAt: now
    )
    
    // Upsert into SwiftData immediately
    let model = try MemoryModel.upsert(from: dto, in: context)
    
    // Save local image paths (for offline cache)
    if !payload.images.isEmpty {
      model.localImagePaths = try persistImagesToFiles(payload.images, dayKey: day.startOfDayUTC)
    } else {
      model.localImagePaths = []
    }
    
    // Save video local path for offline cache
    if let videoURL = payload.videoURL {
      model.downloadURLs.append(videoURL.absoluteString)
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
        var remoteImages: [String] = []
        
        // Upload each image
        for (i, img) in payload.images.enumerated() {
          let url = try await FirebaseStorageManager.uploadImage(
            img.image,
            userID: userID,
            memoryID: memoryID,
            index: i
          )
          remoteImages.append(url.absoluteString)
        }
        
        // Upload video if present
        var videoURLString: String?
        if let videoURL = payload.videoURL {
          let url = try await FirebaseStorageManager.uploadVideo(
            fileURL: videoURL,
            userID: userID,
            memoryID: memoryID
          )
          videoURLString = url.absoluteString
        }
        
        // Build final DTO with remote paths
        var finalDTO = dto
        finalDTO.remoteImagePaths = remoteImages
        if let v = videoURLString {
          finalDTO.downloadURLs.append(v)
        }
        
        // Update local model with remote paths
        await MainActor.run {
          model.remoteImagePaths = remoteImages
          if let v = videoURLString {
            model.downloadURLs.append(v)
          }
          model.updatedAt = Date()
          try? context.save()
        }
        
        // Upload to Firestore
        try await MemoryService.postMemory(model)
        print("✅ Post synced to Firestore with remote URLs")
        
      } catch {
        print("⚠️ Failed uploading media or posting to Firestore: \(error)")
      }
    }
    
    return model
  }
  
  // MARK: - Helpers
  /// Writes UIImages to app's temporary dir as JPEG and returns file paths.
  private func persistImagesToFiles(_ picked: [PickedImage], dayKey: Date) throws -> [String] {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("memories", isDirectory: true)
    
    // Ensure directory exists
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
}
