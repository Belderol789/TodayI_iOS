// src/revokePrivateTokens.ts
//
// One-off migration: revoke download tokens on media belonging to Personal entries.
//
// Every memory uploaded before the client learned the difference called downloadURL()
// unconditionally, so private photos, videos and voice notes all carry a
// `firebaseStorageDownloadTokens` value — and that token bypasses Storage rules. The
// files are still out there and still fetchable by anyone holding a link.
//
// Clearing the metadata invalidates those links permanently. The client already
// tolerates both forms (a tokened URL or a bare storage path), so rewriting the document
// fields to paths is safe for builds that are already shipped.
//
// Run once from the console or the CLI, then delete this function:
//   firebase functions:shell
//   revokePrivateTokens({})

import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const REGION = "asia-southeast1";

/** `https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<encoded path>?...` → path. */
function pathFromURL(value: string): string | null {
  if (!value.startsWith("http")) return value || null;   // already a bare path
  const match = value.match(/\/o\/([^?]+)/);
  return match ? decodeURIComponent(match[1]) : null;
}

export const revokePrivateTokens = onCall(
  { region: REGION, timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    // Callable rather than HTTP so it can't be hit anonymously. Restrict to yourself:
    // set `admin: true` on your own user doc before running, and clear it afterwards.
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    const caller = await admin.firestore().collection("users").doc(uid).get();
    if (caller.get("admin") !== true) {
      throw new HttpsError("permission-denied", "Admin only.");
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    // Collection-group over every user's memories. May need an index on isPublic with
    // collection-group scope — the error will carry a console link if so.
    const snap = await db.collectionGroup("memories").where("isPublic", "==", false).get();

    let filesRevoked = 0;
    let docsRewritten = 0;
    let missing = 0;

    for (const doc of snap.docs) {
      const data = doc.data();
      const images: string[] = Array.isArray(data.remoteImagePaths) ? data.remoteImagePaths : [];
      const single = [data.videoRemoteURL, data.audioRemoteURL].filter(
        (v): v is string => typeof v === "string" && v.length > 0
      );

      const all = [...images, ...single];
      if (all.length === 0) continue;

      const rewritten = new Map<string, string>();
      for (const value of all) {
        const path = pathFromURL(value);
        if (!path) continue;
        rewritten.set(value, path);

        // Already a bare path means a newer client wrote it — nothing to revoke.
        if (!value.startsWith("http")) continue;

        try {
          const file = bucket.file(path);
          const [exists] = await file.exists();
          if (!exists) { missing++; continue; }
          // Empty string, not delete: the Firebase Storage backend treats a blank token
          // list as "no valid token", which is what invalidates existing links.
          await file.setMetadata({ metadata: { firebaseStorageDownloadTokens: "" } });
          filesRevoked++;
        } catch (err) {
          console.error(`   ❌ could not revoke ${path}:`, err);
        }
      }

      const update: Record<string, unknown> = {
        remoteImagePaths: images.map((v) => rewritten.get(v) ?? v),
      };
      if (typeof data.videoRemoteURL === "string") {
        update.videoRemoteURL = rewritten.get(data.videoRemoteURL) ?? data.videoRemoteURL;
      }
      if (typeof data.audioRemoteURL === "string") {
        update.audioRemoteURL = rewritten.get(data.audioRemoteURL) ?? data.audioRemoteURL;
      }
      await doc.ref.update(update);
      docsRewritten++;
    }

    const summary = { scanned: snap.size, docsRewritten, filesRevoked, missing };
    console.log("🔒 revokePrivateTokens complete", summary);
    return summary;
  }
);
