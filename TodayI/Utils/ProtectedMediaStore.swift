//
//  ProtectedMediaStore.swift
//  TodayI
//
//  Fetches media that has no download token, through the authenticated SDK.
//

import Foundation
import FirebaseStorage

/// Downloads rules-protected media and caches it on disk.
///
/// This path is deliberately cold. Local-first means a Personal entry's photo is already
/// in Documents on the device that wrote it, so `imageSources` never reaches here — it
/// only matters after a reinstall or on a second device, which is exactly the case the
/// remote copy exists for.
///
/// Caching to Documents rather than memory means a restored entry pays the download once
/// and then behaves like any other local media.
actor ProtectedMediaStore {
  static let shared = ProtectedMediaStore()

  /// 25 MB ceiling. Enough for a downscaled photo or a voice note; a video would exceed
  /// it, which is why `videoSource` streams instead of going through here.
  private static let maxBytes: Int64 = 25 * 1024 * 1024

  private var inFlight: [String: Task<URL?, Never>] = [:]

  private var cacheDirectory: URL? {
    guard let base = FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    let dir = base.appendingPathComponent("protected", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Returns a local file URL for a storage path, downloading it once if needed.
  func localURL(forPath path: String) async -> URL? {
    guard let dir = cacheDirectory else { return nil }
    // Storage paths contain slashes; flatten so the cache stays one directory deep.
    let name = path.replacingOccurrences(of: "/", with: "_")
    let dest = dir.appendingPathComponent(name)

    if FileManager.default.fileExists(atPath: dest.path) { return dest }
    if let running = inFlight[path] { return await running.value }

    let task = Task<URL?, Never> {
      do {
        LoggerManager.instance.logFirebaseCall()
        let data = try await Storage.storage().reference(withPath: path)
          .data(maxSize: Self.maxBytes)
        try data.write(to: dest, options: .atomic)
        return dest
      } catch {
        print("⚠️ Protected media fetch failed for \(path):", error)
        return nil
      }
    }
    inFlight[path] = task
    let result = await task.value
    inFlight[path] = nil
    return result
  }

  /// Clears the cache — used by the account wipe.
  nonisolated static func clearCache() {
    guard let base = FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    try? FileManager.default.removeItem(
      at: base.appendingPathComponent("protected", isDirectory: true)
    )
  }
}
