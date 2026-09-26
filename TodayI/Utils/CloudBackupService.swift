//
//  CloudBackupService.swift
//  TodayI
//
//  Cloud backup is the Premium feature. This is what backs things up.
//

import Foundation
import SwiftData
import UIKit
import FirebaseFirestore

/// Uploads memories that were saved locally while the user was on the free tier.
///
/// Free users keep Personal entries on device only — which is honest (it costs us
/// nothing, so we don't charge for it) but means a subscription has to be able to pick
/// up everything written before it. `MemoryModel.needsCloudBackup` marks those, and this
/// drains the queue oldest-first so the journal fills in chronologically rather than
/// appearing in random order on a second device.
///
/// It doubles as the retry that `savePostPayload`'s fire-and-forget upload never had: a
/// memory whose upload failed keeps its flag and is retried on the next run.
enum CloudBackupService {

  /// Guards against two drains running at once — subscribing while a launch drain is
  /// already in flight would upload everything twice.
  private static var isRunning = false

  /// Uploads everything still waiting. Safe to call on launch and on entitlement change.
  @MainActor
  static func drain(context: ModelContext, isPremium: Bool, userID: String?) async {
    guard isPremium, let userID, !isRunning else { return }
    isRunning = true
    defer { isRunning = false }

    let pending: [MemoryModel]
    do {
      var fetch = FetchDescriptor<MemoryModel>(
        predicate: #Predicate { $0.needsCloudBackup == true },
        sortBy: [SortDescriptor(\.date, order: .forward)]
      )
      fetch.fetchLimit = 200   // a long-lapsed user could have thousands; chip away
      pending = try context.fetch(fetch)
    } catch {
      print("❌ Backup queue fetch failed:", error)
      return
    }

    guard !pending.isEmpty else { return }
    print("☁️ Backing up \(pending.count) memory(ies)…")

    var succeeded = 0
    for model in pending where model.userID == userID {
      if await backUp(model, context: context) { succeeded += 1 }
    }
    print("☁️ Backup finished — \(succeeded)/\(pending.count) uploaded")
  }

  /// Uploads one memory's media and document. Returns false on any failure, leaving the
  /// flag set so the next drain retries it.
  @MainActor
  private static func backUp(_ model: MemoryModel, context: ModelContext) async -> Bool {
    do {
      // Media comes off disk rather than from a PostPayload — a backfill happens long
      // after the UIImages that created it are gone.
      var remoteImages: [String] = []
      for (i, path) in model.localImagePaths.enumerated() {
        guard let image = UIImage(contentsOfFile: path) else { continue }
        let ref = try await FirebaseStorageManager.uploadImage(
          image, userID: model.userID, memoryID: model.id, index: i,
          isPublic: model.isPublic
        )
        remoteImages.append(ref.stored)
      }

      var videoRemote: String?
      if let path = model.videoLocalPath, FileManager.default.fileExists(atPath: path) {
        videoRemote = try await FirebaseStorageManager.uploadVideo(
          fileURL: URL(fileURLWithPath: path), userID: model.userID,
          memoryID: model.id, isPublic: model.isPublic
        ).stored
      }

      var audioRemote: String?
      if let path = model.audioLocalPath, FileManager.default.fileExists(atPath: path) {
        audioRemote = try await FirebaseStorageManager.uploadAudio(
          fileURL: URL(fileURLWithPath: path), userID: model.userID,
          memoryID: model.id, isPublic: model.isPublic
        ).stored
      }

      model.remoteImagePaths = remoteImages
      if let videoRemote { model.videoRemoteURL = videoRemote }
      if let audioRemote { model.audioRemoteURL = audioRemote }

      try await MemoryService.postMemory(model)

      model.needsCloudBackup = false
      try? context.save()
      return true
    } catch {
      print("⚠️ Backup failed for \(model.id) — will retry:", error)
      return false
    }
  }

  // MARK: - Premium window (for server-side retention)

  /// Records that the user currently has Premium, so the retention job on the server can
  /// tell an active subscriber from one who lapsed.
  ///
  /// StoreKit entitlements live on the device; Firestore has no idea who is subscribed.
  /// Rather than build receipt validation, the client stamps its own user document. A
  /// user could forge this, but the only thing forging buys them is keeping *their own*
  /// backup alive longer — so it isn't worth defending against.
  static func recordPremiumWindow(isPremium: Bool, userID: String?) async {
    guard isPremium, let userID else { return }
    do {
      LoggerManager.instance.logFirebaseCall()
      try await Firestore.firestore().collection("users").document(userID).setData(
        ["premiumLastSeenAt": FieldValue.serverTimestamp()], merge: true
      )
    } catch {
      print("⚠️ Could not stamp premium window:", error)
    }
  }
}
