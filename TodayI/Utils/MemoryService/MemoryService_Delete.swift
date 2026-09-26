import FirebaseFirestore
import FirebaseStorage
import SwiftData

extension MemoryService {

  /// How far a delete should reach.
  ///
  /// Journals are not feeds: "I want this off the internet" and "I want this gone" are
  /// different wishes, and collapsing them into one button forces people to destroy a
  /// memory in order to un-share it.
  enum DeleteScope {
    /// Remove it from Firestore and Storage; keep the copy on this device.
    case remoteOnly
    /// Remove it everywhere, including this device.
    case everywhere

    var confirmationMessage: String {
      switch self {
      case .remoteOnly:
        return "This removes the post from the cloud and the Global feed. Your copy stays on this device, but it won't sync to a new phone."
      case .everywhere:
        return "This permanently removes the post from this device and the cloud. This cannot be undone."
      }
    }
  }

  enum DeleteError: LocalizedError {
    case couldNotKeepLocalCopy
    var errorDescription: String? {
      "This memory's photos or video are only in the cloud, and they couldn't be downloaded to this device. Nothing was deleted — check your connection and try again."
    }
  }

  /// Deletes a memory at the requested scope.
  ///
  /// The remote half is identical either way — Firestore doc plus Storage files. Only
  /// the local record differs.
  ///
  /// The `comments/{memoryId}` hub and its replies are *not* deleted here: client rules
  /// grant no delete on the hub and only permit deleting your own replies, so the client
  /// physically cannot clean up a thread containing other people's comments. The
  /// `onMemoryDeleted` Cloud Function does it with the Admin SDK once the memory doc
  /// disappears.
  static func deleteMemory(
    _ memory: MemoryModel,
    scope: DeleteScope = .everywhere,
    context: ModelContext
  ) async throws {
    let db = Firestore.firestore()
    let storage = Storage.storage()
    LoggerManager.instance.logFirebaseCall()

    // 0. "Keep my copy" has to be true before anything is destroyed.
    //
    // `MemoryModel.upsert` creates cloud-sourced memories with `localImageNames: []`,
    // so anything restored after a reinstall, synced from another device, or seen in the
    // feed lives *only* in Storage. `imageSources` falls back to the remote copy, so it
    // looks fine right up until the remote copy is removed — at which point the media is
    // gone for good while the text stays, because the text was in SwiftData all along.
    //
    // Pull the media down first, and refuse rather than delete the last copy.
    if scope == .remoteOnly {
      guard await materializeLocally(memory) else {
        throw DeleteError.couldNotKeepLocalCopy
      }
    }

    // 1. Firestore doc.
    let memRef = db.collection("users").document(memory.userID)
      .collection("memories").document(memory.id)
    try await memRef.delete()

    // 2. Storage files — best-effort, so one missing object can't strand the rest.
    var storagePaths: [String] = []
    storagePaths += memory.remoteImagePaths
    if let v = memory.videoRemoteURL { storagePaths.append(v) }
    if let a = memory.audioRemoteURL { storagePaths.append(a) }

    await withTaskGroup(of: Void.self) { group in
      for path in storagePaths {
        group.addTask {
          do {
            let ref = path.hasPrefix("gs://") || path.hasPrefix("http")
              ? storage.reference(forURL: path)
              : storage.reference(withPath: path)
            try await ref.delete()
          } catch {
            print("⚠️ Could not delete storage file:", path, error)
          }
        }
      }
    }

    // 3. The local record.
    await MainActor.run {
      switch scope {
      case .everywhere:
        // Without this the media stays in Documents forever with nothing referencing it.
        removeLocalFiles(memory)
        context.delete(memory)

      case .remoteOnly:
        // Strip every remote pointer. `imageSources` / `videoSource` / `audioSource`
        // prefer local and fall back to remote, so leaving these set would make the row
        // chase URLs that now 404.
        memory.remoteImagePaths = []
        memory.videoRemoteURL = nil
        memory.audioRemoteURL = nil
        // It can't be in the Global feed if it isn't on the server; keeping the flag set
        // would also re-publish it the moment anything upserts this record.
        memory.isPublic = false
        memory.updatedAt = .now

        NotificationCenter.default.post(
          name: .memoryPrivacyDidChange,
          object: nil,
          userInfo: ["id": memory.id, "isPublic": false]
        )
      }
      try? context.save()
    }

    // The day itself still happened, so `users/{uid}/dates/{dayKey}` is deliberately left
    // alone — it carries moods for the calendar, never content, and other memories from
    // the same day may still rely on it.
  }
}
