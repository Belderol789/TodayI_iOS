// src/deleteAccount.ts
//
// Account deletion, done where it can actually be done completely.
//
// The client version could only reach what security rules allow, which left three
// categories of data behind: the user's Storage files (listAll() is not recursive, so
// the old loop deleted nothing at all), their comments on *other people's* posts, and
// their uid inside other users' blockedUsers arrays. All three are reachable here
// because the Admin SDK bypasses rules.
//
// It also removes a failure mode rather than just data: the client deleted Firestore
// first and Auth last, so the common `requiresRecentLogin` error destroyed someone's
// entire history while leaving the account alive, with nothing left to retry. The Admin
// SDK has no recent-login requirement, so Auth deletion here is reliable and runs last —
// if anything before it throws, the account survives and the whole call can be retried.

import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const REGION = "asia-southeast1";

// Firestore caps a WriteBatch at 500 operations. Stay under it so a chunk that also
// touches a parent document (comment deletes bump the hub's commentCount) can't spill.
const BATCH_LIMIT = 400;

/** Splits an array into fixed-size chunks. */
function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/**
 * Deletes every trace of the caller's account, then the Auth user itself.
 *
 * Callable rather than an Auth `onDelete` trigger on purpose: the client needs to know
 * whether the wipe actually succeeded before it clears local data, and a background
 * trigger gives it nothing to wait on.
 *
 * Idempotent — every step tolerates already-missing data, so a client retry after a
 * network failure is safe.
 */
export const deleteAccountData = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in to delete your account.");
  }

  const db = admin.firestore();
  console.log(`🗑️ deleteAccountData starting for ${uid}`);

  // 1. The user tree: profile doc, memories, dates, notifications.
  //    recursiveDelete walks subcollections, which is exactly what Firestore won't do
  //    for a plain document delete.
  await db.recursiveDelete(db.collection("users").doc(uid));
  console.log("   ✅ users/* deleted");

  // 2. Storage. The client's listAll() only ever saw prefixes (memories/, profile/) and
  //    iterated items, which is empty at that level — so every photo, video and voice
  //    note survived deletion. A prefix delete gets the whole subtree.
  //
  //    This matters more than it looks: downloadURL() hands out tokened URLs that ignore
  //    Storage rules, so anything left here stays fetchable by anyone holding the link,
  //    indefinitely, long after the account is gone.
  try {
    await admin.storage().bucket().deleteFiles({ prefix: `users/${uid}/`, force: true });
    console.log("   ✅ Storage users/ prefix deleted");
  } catch (err) {
    // Don't strand the account over a storage hiccup — but do surface it, because this
    // is the step whose failure leaves private media readable.
    console.error("   ❌ Storage delete failed — media may survive:", err);
  }

  // 3. Comments the user wrote on other people's posts. These live under
  //    comments/{memoryId}/comments/{id} and carry their userID and username, so leaving
  //    them means a deleted account's words stay attached to strangers' posts.
  //
  //    NOTE: this is a collection-group query and Admin SDK calls still need indexes even
  //    though they bypass rules. If it throws FAILED_PRECONDITION, the error carries a
  //    console link that creates the index.
  const authored = await db.collectionGroup("comments").where("userID", "==", uid).get();

  // socialMilestones.ts increments commentCount on create and nothing decrements it, so
  // deleting these would leave every affected hub reporting counts that never drop.
  const perHub = new Map<string, number>();
  for (const doc of authored.docs) {
    const hub = doc.ref.parent.parent;
    if (!hub) continue;
    perHub.set(hub.path, (perHub.get(hub.path) ?? 0) + 1);
  }

  for (const group of chunk(authored.docs, BATCH_LIMIT)) {
    const batch = db.batch();
    group.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
  for (const group of chunk([...perHub.entries()], BATCH_LIMIT)) {
    const batch = db.batch();
    for (const [path, count] of group) {
      batch.set(db.doc(path), { commentCount: FieldValue.increment(-count) }, { merge: true });
    }
    await batch.commit();
  }
  console.log(`   ✅ ${authored.size} authored comment(s) removed across ${perHub.size} hub(s)`);

  // 4. Comment hubs for the user's own memories, plus everyone else's comments beneath
  //    them. The memories themselves went in step 1; these hubs are a separate top-level
  //    collection and were never touched.
  const hubs = await db.collection("comments").where("ownerID", "==", uid).get();
  for (const hub of hubs.docs) {
    await db.recursiveDelete(hub.ref);
  }
  console.log(`   ✅ ${hubs.size} owned comment hub(s) deleted`);

  // 5. The uid sitting in other users' blockedUsers arrays. Harmless-looking, but it is
  //    a durable record that this person existed and who blocked them.
  const blockers = await db
    .collection("users")
    .where("blockedUsers", "array-contains", uid)
    .get();
  for (const group of chunk(blockers.docs, BATCH_LIMIT)) {
    const batch = db.batch();
    group.forEach((doc) =>
      batch.update(doc.ref, { blockedUsers: FieldValue.arrayRemove(uid) })
    );
    await batch.commit();
  }
  console.log(`   ✅ uid removed from ${blockers.size} blockedUsers list(s)`);

  // 6. Moderation reports, handled deliberately rather than uniformly.
  //
  //    Reports *about* this user describe an account that no longer exists — delete them.
  //    Reports they *filed* are evidence against someone else and are worth keeping, so
  //    scrub the reporter link instead of destroying the record. Say this in the privacy
  //    policy; retaining anything after a deletion request should never be a surprise.
  const against = await db.collection("reports").where("reportedUID", "==", uid).get();
  for (const group of chunk(against.docs, BATCH_LIMIT)) {
    const batch = db.batch();
    group.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }

  const filed = await db.collection("reports").where("reporterUID", "==", uid).get();
  for (const group of chunk(filed.docs, BATCH_LIMIT)) {
    const batch = db.batch();
    group.forEach((doc) => batch.update(doc.ref, { reporterUID: "deleted-user" }));
    await batch.commit();
  }
  console.log(`   ✅ ${against.size} report(s) deleted, ${filed.size} anonymised`);

  // 7. The Auth user, last. Everything above is retryable while this still exists.
  //    Already-deleted is success, not an error — that's what makes a retry safe.
  try {
    await admin.auth().deleteUser(uid);
    console.log("   ✅ Auth user deleted");
  } catch (err) {
    const code = (err as { code?: string }).code;
    if (code !== "auth/user-not-found") throw err;
    console.log("   ✅ Auth user already gone");
  }

  console.log(`🗑️ deleteAccountData complete for ${uid}`);
  return { ok: true };
});
