import FirebaseFirestore
import FirebaseAuth

extension MemoryService {
  /// Update the public/private flag of a memory.
  /// - Note: Rules must allow owner updates (your current rules do).
  static func updatePrivacy(
    userID: String,
    memoryID: String,
    isPublic: Bool,
    db: Firestore = .firestore()
  ) async throws {
    let ref = db.collection("users").document(userID)
      .collection("memories").document(memoryID)

    try await ref.updateData([
      "isPublic": isPublic,
      "updatedAt": FieldValue.serverTimestamp()
    ])
  }

  /// Flips privacy **and** the reachability of the memory's media.
  ///
  /// The flag alone only hides a post from the feed. Its photos, video and voice note
  /// keep whatever download token they were uploaded with, and that token bypasses
  /// Storage rules — so a post switched back to Personal stayed fetchable forever by
  /// anyone who had the link. Moving to Personal now **revokes** the token, which
  /// invalidates every link already handed out; moving to Global mints one.
  ///
  /// Media is converted before the Firestore write, so a failure part-way leaves the post
  /// in its previous state rather than advertising media that is no longer reachable —
  /// or worse, marking it Personal while the links still work.
  static func updatePrivacy(
    for memory: MemoryModel,
    isPublic: Bool,
    db: Firestore = .firestore()
  ) async throws {
    // Fast path: a free user's Personal entry was never uploaded, so there is nothing
    // to patch. Making it Global means uploading it for the first time.
    if memory.needsCloudBackup {
      try await firstUpload(memory, isPublic: isPublic)
      return
    }

    var images: [String] = []
    for stored in memory.remoteImagePaths {
      images.append(try await convert(stored, toPublic: isPublic))
    }
    let video = try await memory.videoRemoteURL.asyncMap { try await convert($0, toPublic: isPublic) }
    let audio = try await memory.audioRemoteURL.asyncMap { try await convert($0, toPublic: isPublic) }

    let ref = db.collection("users").document(memory.userID)
      .collection("memories").document(memory.id)
    do {
      let batch = db.batch()
      batch.updateData([
        "isPublic": isPublic,
        "remoteImagePaths": images,
        "videoRemoteURL": video as Any,
        "audioRemoteURL": audio as Any,
        "updatedAt": FieldValue.serverTimestamp()
      ], forDocument: ref)
      // A Personal memory has no comment hub (see `postMemory`), so going Global is when
      // it gets one — in the same batch, so the post can't be commentable without it.
      // Going Personal leaves any existing hub alone: its comments come back if the post
      // is shared again.
      if isPublic {
        batch.setData(commentsHubPayload(memoryID: memory.id,
                                         ownerID: memory.userID,
                                         isPublic: true,
                                         dayKey: memory.dayKey),
                      forDocument: db.collection("comments").document(memory.id),
                      merge: true)
      }
      try await batch.commit()
    } catch let error as NSError where error.code == FirestoreErrorCode.notFound.rawValue {
      // The document isn't there. Either "Remove from Cloud Only" took it, or the flag
      // is out of step with reality. Re-create it in full rather than patching nothing —
      // a partial `setData` would leave a document with no text or mood.
      try await firstUpload(memory, isPublic: isPublic)
      return
    }

    await MainActor.run {
      memory.remoteImagePaths = images
      memory.videoRemoteURL = video
      memory.audioRemoteURL = audio
    }
  }

  /// Uploads a memory that has no document in Firestore yet.
  ///
  /// Reached two ways: a free user's local-only entry going Global, and a memory whose
  /// remote copy was removed by `deleteMemory(scope: .remoteOnly)` and is now being
  /// shared again. Both need a full write, not an update.
  private static func firstUpload(_ memory: MemoryModel, isPublic: Bool) async throws {
    // Going Personal needs no server work at all — there is nothing up there.
    guard isPublic else {
      await MainActor.run {
        memory.isPublic = false
        try? memory.modelContext?.save()
      }
      return
    }

    // See the identical guard in `CloudBackupService.backUp` — same failure mode, hit
    // from the other call path (sharing a memory that was created under a different
    // signed-in account than the one active now, or after `deleteMemory(.remoteOnly)`
    // removed the document and a later re-share tries to recreate it).
    guard Auth.auth().currentUser?.uid == memory.userID else {
      throw PrivacyError.wrongAccount
    }

    await MainActor.run { memory.isPublic = isPublic }
    guard await CloudBackupService.backUpNow(memory) else {
      // Put it back. Showing "Global" when nothing reached the server is a lie the user
      // cannot see through.
      await MainActor.run { memory.isPublic = false }
      throw PrivacyError.uploadFailed
    }
  }

  private static func convert(_ stored: String, toPublic: Bool) async throws -> String {
    toPublic
      ? try await FirebaseStorageManager.makePublic(stored: stored)
      : try await FirebaseStorageManager.makeProtected(stored: stored)
  }
}

extension MemoryService {
  enum PrivacyError: LocalizedError {
    case uploadFailed
    /// This memory was created under a different signed-in account than the one active
    /// now — the write would land in a path that no longer belongs to this session, and
    /// Storage rules correctly deny it. Surfacing this instead of a raw 403 is the whole
    /// point; see `CloudBackupService.backUp`'s matching guard for how it's found.
    case wrongAccount
    var errorDescription: String? {
      switch self {
      case .uploadFailed:
        return "Couldn't share this memory. Check your connection and try again."
      case .wrongAccount:
        return "This memory belongs to a different account than the one currently signed in, so it can't be shared from here."
      }
    }
  }
}

private extension Optional where Wrapped == String {
  /// `map` that can await — Optional.map takes a non-async closure.
  func asyncMap(_ transform: (String) async throws -> String) async rethrows -> String? {
    guard let self else { return nil }
    return try await transform(self)
  }
}
