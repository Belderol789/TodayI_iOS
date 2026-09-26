import FirebaseFirestore

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
    var images: [String] = []
    for stored in memory.remoteImagePaths {
      images.append(try await convert(stored, toPublic: isPublic))
    }
    let video = try await memory.videoRemoteURL.asyncMap { try await convert($0, toPublic: isPublic) }
    let audio = try await memory.audioRemoteURL.asyncMap { try await convert($0, toPublic: isPublic) }

    let ref = db.collection("users").document(memory.userID)
      .collection("memories").document(memory.id)
    try await ref.updateData([
      "isPublic": isPublic,
      "remoteImagePaths": images,
      "videoRemoteURL": video as Any,
      "audioRemoteURL": audio as Any,
      "updatedAt": FieldValue.serverTimestamp()
    ])

    await MainActor.run {
      memory.remoteImagePaths = images
      memory.videoRemoteURL = video
      memory.audioRemoteURL = audio
    }
  }

  private static func convert(_ stored: String, toPublic: Bool) async throws -> String {
    toPublic
      ? try await FirebaseStorageManager.makePublic(stored: stored)
      : try await FirebaseStorageManager.makeProtected(stored: stored)
  }
}

private extension Optional where Wrapped == String {
  /// `map` that can await — Optional.map takes a non-async closure.
  func asyncMap(_ transform: (String) async throws -> String) async rethrows -> String? {
    guard let self else { return nil }
    return try await transform(self)
  }
}
