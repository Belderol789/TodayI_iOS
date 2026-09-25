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
  
  /// The cached profile row, if this device has one. Used by paths that must not
  /// touch the network, such as the notification mood actions.
  func localUser(id: String) -> UserModel? {
    var fetch = FetchDescriptor<UserModel>(predicate: #Predicate { $0.id == id })
    fetch.fetchLimit = 1
    return (try? context.fetch(fetch))?.first
  }

  /// Cheap existence check for today, used by the notification mood actions before
  /// they write — the app may be running in the background with no view loaded.
  func hasMemoryToday(userID: String, in tz: TimeZone = .current) -> Bool {
    let key = Date().today.formattedDayKeyLocal(in: tz)
    var fetch = FetchDescriptor<MemoryModel>(
      predicate: #Predicate { $0.dayKey == key && $0.userID == userID }
    )
    fetch.fetchLimit = 1
    return ((try? context.fetch(fetch).first) ?? nil) != nil
  }

  func fetchAllMemories() throws -> [MemoryModel] {
    let fetch = FetchDescriptor<MemoryModel>()
    return try context.fetch(fetch)
  }

  /// A random memory from any day *before* `todayKey`, drawn from what's already
  /// stored locally — no network. Returns nil when this device has never imported a
  /// past day, which is the cue for `HomeView` to pull one day down.
  func randomPastMemory(excluding todayKey: String, userID: String?) throws -> MemoryModel? {
    let predicate: Predicate<MemoryModel>
    if let id = userID, !id.isEmpty {
      predicate = #Predicate { $0.userID == id && $0.dayKey != todayKey }
    } else {
      predicate = #Predicate { $0.dayKey != todayKey }
    }
    return try context.fetch(FetchDescriptor<MemoryModel>(predicate: predicate)).randomElement()
  }

  /// Day keys the user has recorded a mood on, before today. `DateModel` is synced
  /// once per launch, so this is a free index of which past days are worth fetching.
  func pastDayKeys(before today: Date, in tz: TimeZone = .current) throws -> [String] {
    let start = today.startOfDay(in: tz)
    let rows = try context.fetch(
      FetchDescriptor<DateModel>(predicate: #Predicate { $0.date < start })
    )
    return rows.map { $0.date.formattedDayKeyLocal(in: tz) }
  }

  /// Repairs rows whose `dayKey` disagrees with their own `date`.
  ///
  /// `MemoryModel.init` used to stamp `dayKey` from `Date()`, and `upsert` never
  /// overrode it on insert — so every memory imported from Firestore was filed under
  /// the day it happened to be imported, and opening any day showed the whole history.
  /// Both are fixed, but stores written by earlier builds still hold the bad keys, so
  /// correct them in place. The key is recomputed in the memory's *author* timezone,
  /// which is the one `date` was normalized to when it was created.
  @discardableResult
  func repairMismatchedDayKeys() -> Int {
    do {
      let rows = try fetchAllMemories()
      var fixed = 0
      for row in rows {
        let tz = TimeZone(identifier: row.authorTZ) ?? .current
        let expected = row.date.formattedDayKeyLocal(in: tz)
        if row.dayKey != expected {
          print("🩹 dayKey repair \(row.id.prefix(8)): \(row.dayKey) → \(expected)")
          row.dayKey = expected
          fixed += 1
        }
      }
      if fixed > 0 { try context.save() }
      return fixed
    } catch {
      print("⚠️ repairMismatchedDayKeys error:", error)
      return 0
    }
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

    // Persist local audio (offline cache)
    if let audioURL = payload.audioURL {
      let localPath = try persistAudioToFiles(audioURL, dayKey: dayStartLocal)
      model.audioLocalPath = localPath
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
  
  private func persistAudioToFiles(_ originalURL: URL, dayKey: Date) throws -> String {
    let base = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("audio", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let ext = originalURL.pathExtension.isEmpty ? "m4a" : originalURL.pathExtension
    let name = "\(Int(dayKey.timeIntervalSince1970))-\(UUID().uuidString).\(ext)"
    let dest = base.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: dest.path) {
      try FileManager.default.removeItem(at: dest)
    }
    try FileManager.default.copyItem(at: originalURL, to: dest)
    return dest.path
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
