import FirebaseFirestore
import FirebaseStorage
import SwiftData

extension MemoryService {
  /// Deletes a memory from Firestore, removes any associated Storage files,
  /// and deletes the local SwiftData record.
  static func deleteMemory(_ memory: MemoryModel, context: ModelContext) async throws {
    let db = Firestore.firestore()
    let storage = Storage.storage()

    // 1. Delete Firestore doc (comments subcollection is cleaned up by Cloud Functions or can be left orphaned)
    let memRef = db.collection("users").document(memory.userID)
      .collection("memories").document(memory.id)
    try await memRef.delete()

    // 2. Delete Storage files (best-effort — don't fail the whole operation if one file is missing)
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

    // 3. Delete local SwiftData record
    await MainActor.run {
      context.delete(memory)
      try? context.save()
    }
  }
}
