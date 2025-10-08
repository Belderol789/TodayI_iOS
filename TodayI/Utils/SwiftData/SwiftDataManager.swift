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
  
  @discardableResult
  func savePostPayload(_ payload: PostPayload,
                       userID: String,
                       username: String,
                       for day: Date = .now) throws -> MemoryModel {
    // 1) Save locally (SwiftData) first
    let (model, dto, dayStartLocal) = try saveToSwiftData(payload, userID: userID, username: username, day: day)
    
    // 2) Kick off background upload to Firebase (private)
    Task {
      await uploadToFirebase(dto: dto,
                             payload: payload,
                             model: model,
                             userID: userID,
                             dayStartLocal: dayStartLocal)
    }
    
    return model
  }
  
  // MARK: - Local save (SwiftData)
  
  /// Saves to SwiftData immediately (images/videos to local cache, mood to DateModel, etc.)
  /// Returns the upserted model, the initial DTO, and the computed dayStartLocal.
  private func saveToSwiftData(_ payload: PostPayload,
                               userID: String,
                               username: String,
                               day: Date) throws -> (MemoryModel, MemoryDTO, Date) {
    let authorTZ = TimeZone.current
    let now = Date()
    let memoryID = UUID().uuidString
    let dayStartLocal = day.startOfDay(in: authorTZ)
    
    // Initial DTO (remote fields empty for now)
    var dto = MemoryDTO(payload: payload,
                        userID: userID,
                        username: username,
                        day: day)
    
    // Upsert into SwiftData
    let model = try MemoryModel.upsert(from: dto, in: context)
    
    // Persist local images (offline cache)
    if !payload.images.isEmpty {
      model.localImagePaths = try persistImagesToFiles(payload.images, dayKey: dayStartLocal)
    } else {
      model.localImagePaths = []
    }
    
    // Persist local video (offline cache)
    if let videoURL = payload.videoURL {
      let localPath = try persistVideoToFiles(videoURL, dayKey: dayStartLocal)
      model.videoLocalPath = localPath
    }
    
    // Save link (if any)
    if let link = payload.linkString {
      model.linkURL = link
    }
    
    // Update DateModel (append mood)
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
    
    return (model, dto, dayStartLocal)
  }
  
  // MARK: - Firebase sync (private)
  
  /// Uploads media to Firebase Storage, updates the local model with remote URLs,
  /// and posts to Firestore. Runs on a background Task from the caller.
  private func uploadToFirebase(dto: MemoryDTO,
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

extension SwiftDataManager {
  func importMemoriesIfNeeded(_ dtos: [MemoryDTO]) throws {
    for dto in dtos {
      // Build a typed fetch descriptor
      var fetch = FetchDescriptor<MemoryModel>(
        predicate: #Predicate<MemoryModel> { $0.id == dto.id }
      )
      fetch.fetchLimit = 1   // 👈 assign separately
      
      let existing: [MemoryModel] = try context.fetch(fetch)
      if existing.first == nil {
        _ = try MemoryModel.upsert(from: dto, in: context)
      }
    }
    try context.save()
  }
  
  func importDatesIfNeeded(_ dtos: [DateDTO]) throws {
    for dto in dtos {
      let fetch = FetchDescriptor<DateModel>(
        predicate: #Predicate { $0.date == dto.date }
      )
      if try context.fetch(fetch).isEmpty {
        let moods = dto.moodRaws.compactMap { Mood(rawValue: $0) }
        let model = DateModel(date: dto.date, moods: moods)
        context.insert(model)
      }
    }
    try context.save()
  }
}
