import Foundation
import FirebaseStorage
import SwiftData

extension MemoryService {

  /// Pulls a memory's media onto this device so the local copy is real.
  ///
  /// `MemoryModel.upsert` creates cloud-sourced memories with `localImageNames: []` —
  /// anything restored after a reinstall, synced from another device, or seen in the
  /// Global feed exists **only** in Storage. `imageSources` then falls back to the
  /// remote copy and everything looks fine, which hides the problem until something
  /// removes the remote copy.
  ///
  /// That made "Remove from Cloud Only" destructive: it promised the copy on this device
  /// would stay, when for those memories there was no copy on this device at all.
  ///
  /// Returns false if anything could not be fetched, so callers can refuse to proceed
  /// rather than delete the last copy of something.
  @discardableResult
  static func materializeLocally(_ memory: MemoryModel) async -> Bool {
    var allOK = true

    // Images — `localImageNames` holds bare filenames under Documents/memories.
    if memory.localImagePaths.filter({ FileManager.default.fileExists(atPath: $0) }).isEmpty,
       !memory.remoteImagePaths.isEmpty {
      var names: [String] = []
      for (index, stored) in memory.remoteImagePaths.enumerated() {
        let name = "\(memory.id)-\(index).jpg"
        if await download(stored, to: folder("memories").appendingPathComponent(name)) {
          names.append(name)
        } else {
          allOK = false
        }
      }
      if !names.isEmpty {
        await MainActor.run { memory.localImageNames = names }
      }
    }

    // Video and audio hold full paths, not names.
    if !exists(memory.videoLocalPath), let stored = memory.videoRemoteURL {
      let dest = folder("videos").appendingPathComponent("\(memory.id).mp4")
      if await download(stored, to: dest) {
        await MainActor.run { memory.videoLocalPath = dest.path }
      } else {
        allOK = false
      }
    }

    if !exists(memory.audioLocalPath), let stored = memory.audioRemoteURL {
      let ext = (stored as NSString).pathExtension.isEmpty ? "m4a" : (stored as NSString).pathExtension
      let dest = folder("audio").appendingPathComponent("\(memory.id).\(ext)")
      if await download(stored, to: dest) {
        await MainActor.run { memory.audioLocalPath = dest.path }
      } else {
        allOK = false
      }
    }

    await MainActor.run { try? memory.modelContext?.save() }
    return allOK
  }

  /// Removes a memory's media from this device. Used by a full delete, which otherwise
  /// leaves orphaned files in Documents forever.
  static func removeLocalFiles(_ memory: MemoryModel) {
    for path in memory.localImagePaths {
      try? FileManager.default.removeItem(atPath: path)
    }
    if let path = memory.videoLocalPath { try? FileManager.default.removeItem(atPath: path) }
    if let path = memory.audioLocalPath { try? FileManager.default.removeItem(atPath: path) }
  }

  // MARK: - Helpers

  private static func exists(_ path: String?) -> Bool {
    guard let path else { return false }
    return FileManager.default.fileExists(atPath: path)
  }

  private static func folder(_ name: String) -> URL {
    let dir = FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask).first!
      .appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Streams one object to disk. Goes through the Storage SDK rather than `URLSession`
  /// so it works for both forms: a tokened public URL *and* a bare protected path, which
  /// has no token and needs the caller's credentials.
  private static func download(_ stored: String, to destination: URL) async -> Bool {
    if FileManager.default.fileExists(atPath: destination.path) { return true }
    do {
      LoggerManager.instance.logFirebaseCall()
      let ref = FirebaseStorageManager.reference(forStored: stored)
      // write(toFile:) streams, so a large video doesn't have to fit in memory the way
      // `data(maxSize:)` requires.
      _ = try await ref.writeAsync(toFile: destination)
      return true
    } catch {
      print("⚠️ Could not materialize \(stored):", error)
      return false
    }
  }
}

private extension StorageReference {
  /// `write(toFile:)` has no async overload in the SDK.
  func writeAsync(toFile url: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      write(toFile: url) { result, error in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: result ?? url) }
      }
    }
  }
}
