//
//  SwiftData_Memories.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/19/25.
//

import SwiftData
import Foundation

// MARK: - MemoryModel
extension SwiftDataManager {
  /// Load memories for a given date.
  /// Premium => all; Free => only the latest
  func loadMemories(for date: Date, userID: String?) throws -> [MemoryModel] {
    let cal = Calendar.current
    let key = cal.startOfDay(for: date)
    
    let predicate: Predicate<MemoryModel>
    
    if let id = userID, !id.isEmpty {
      predicate = #Predicate {
        $0.date == key && $0.userID == id
      }
    } else {
      predicate = #Predicate {
        $0.date == key
      }
    }
    
    let fetch = FetchDescriptor<MemoryModel>(
      predicate: predicate,
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )
    
    let rows = try context.fetch(fetch)
    return store.isPremium ? rows : (rows.last.map { [$0] } ?? [])
  }
  
  func fetchAllMemories() throws -> [MemoryModel] {
    let fetch = FetchDescriptor<MemoryModel>()
    return try context.fetch(fetch)
  }
  
}

// MARK: - PostPayload
extension SwiftDataManager {
  
  @discardableResult
  func savePostPayload(_ payload: PostPayload,
                       userID: String,
                       username: String,
                       remoteProfilePhotoURL: String?,
                       for day: Date = .now) throws -> MemoryModel {
    // 1) Save locally (SwiftData) first
    let (model, dto, dayStartLocal) = try saveToSwiftData(payload, userID: userID, username: username, remoteProfilePhotoURL: remoteProfilePhotoURL, day: day)
    
    // 2) Kick off background upload to Firebase (private)
    Task {
      await FirebaseFirestoreManager.uploadToFirebase(context: context,
                                                      dto: dto,
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
                               remoteProfilePhotoURL: String?,
                               day: Date) throws -> (MemoryModel, MemoryDTO, Date) {
    let authorTZ = TimeZone.current
    let dayStartLocal = day.startOfDay(in: authorTZ)
    
    // Initial DTO (remote fields empty for now)
    let dto = MemoryDTO(payload: payload,
                        userID: userID,
                        username: username,
                        remoteProfilePhotoURL: remoteProfilePhotoURL,
                        day: day)
    
    // Upsert into SwiftData
    let model = try MemoryModel.upsert(from: dto, in: context)
    
    // Persist local images (offline cache)
    if !payload.images.isEmpty {
      model.localImageNames = try persistImagesToFiles(payload.images, dayKey: dayStartLocal)
    } else {
      model.localImageNames = []
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

  // MARK: - Helpers
  /// Writes UIImages to app's temporary dir as JPEG and returns file paths.
  private func persistImagesToFiles(_ picked: [PickedImage], dayKey: Date) throws -> [String] {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      .appendingPathComponent("memories", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    
    var names: [String] = []
    for item in picked {
      guard let data = item.image.jpegData(compressionQuality: 0.85) else { continue }
      let name = "\(Int(dayKey.timeIntervalSince1970))-\(UUID().uuidString).jpg"
      let url = dir.appendingPathComponent(name)
      try data.write(to: url, options: .atomic)
      names.append(name) // ✅ Just store name
    }
    return names
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

// MARK: - MemoryDTO
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
}
