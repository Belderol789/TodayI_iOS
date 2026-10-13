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
import * as functionsV1 from "firebase-functions/v1";

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
 * Removes everything stored for `uid` except the Auth user itself.
 *
 * Shared by `deleteAccountData` (the in-app Delete Account) and `onAuthUserDeleted` (any
 * other way an Auth user disappears), so the two can never drift apart. Idempotent: every
 * step tolerates already-missing data, which matters because the callable's own Auth
 * deletion fires `onAuthUserDeleted`, and that second pass finds nothing left.
 */
export async function wipeUserData(uid: string): Promise<void> {
  const db = admin.firestore();
  console.log(`🗑️ wipeUserData starting for ${uid}`);

  // 0. Every query first, before anything is deleted.
  //
  // The queries are the steps that can fail on configuration rather than data — the
  // collection-group query on comments needs an index, and Admin SDK calls need indexes
  // even though they bypass rules. When that index was missing, the old order had
  // already deleted users/* and the Storage folder before the query threw: the account
  // was half-erased, the Auth user survived, and the app told the person "nothing was
  // removed." Gathering everything up front means a failure here leaves nothing
  // touched, so the honest error message stays honest and a retry starts clean.
  const [authored, hubs, blockers, against, filed, names] = await Promise.all([
    // Comments the user wrote on other people's posts — they carry their userID and
    // username, so leaving them keeps a deleted account's words on strangers' posts.
    db.collectionGroup("comments").where("userID", "==", uid).get(),
    // Hubs for the user's own memories, plus everyone else's comments beneath them.
    db.collection("comments").where("ownerID", "==", uid).get(),
    // The uid inside other users' blockedUsers — a durable record of who blocked them.
    db.collection("users").where("blockedUsers", "array-contains", uid).get(),
    // Reports about this user, and reports they filed (handled differently below).
    db.collection("reports").where("reportedUID", "==", uid).get(),
    db.collection("reports").where("reporterUID", "==", uid).get(),
    // Username claims (usernames.ts), so a deleted account's name is free again.
    db.collection("usernames").where("uid", "==", uid).get(),
  ]);
  console.log(`   🔎 found ${authored.size} authored comment(s), ${hubs.size} hub(s), ` +
    `${blockers.size} blocker(s), ${against.size} report(s) about, ${filed.size} filed`);

  // 1. The user tree: profile doc, memories (Global ones included), dates, notifications.
  //    recursiveDelete walks subcollections, which a plain document delete won't.
  await db.recursiveDelete(db.collection("users").doc(uid));
  console.log("   ✅ users/* deleted");

  // 2. Storage. A prefix delete gets the whole subtree — listAll() is not recursive,
  //    which is why the old client-side version deleted nothing. Anything left here
  //    stays fetchable by anyone holding a tokened downloadURL, indefinitely.
  try {
    await admin.storage().bucket().deleteFiles({ prefix: `users/${uid}/`, force: true });
    console.log("   ✅ Storage users/ prefix deleted");
  } catch (err) {
    // Don't strand the account over a storage hiccup — but surface it, because this is
    // the step whose failure leaves private media readable.
    console.error("   ❌ Storage delete failed — media may survive:", err);
  }

  // 3. Authored comments. socialMilestones.ts increments commentCount on create and
  //    nothing decrements it, so each affected hub is decremented to match.
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

  // 4. Owned hubs and the threads under them.
  for (const hub of hubs.docs) {
    await db.recursiveDelete(hub.ref);
  }
  console.log(`   ✅ ${hubs.size} owned comment hub(s) deleted`);

  // 5. The uid in other users' blockedUsers arrays.
  for (const group of chunk(blockers.docs, BATCH_LIMIT)) {
    const batch = db.batch();
    group.forEach((doc) =>
      batch.update(doc.ref, { blockedUsers: FieldValue.arrayRemove(uid) })
    );
    await batch.commit();
  }
  console.log(`   ✅ uid removed from ${blockers.size} blockedUsers list(s)`);

  // 6. Reports, deliberately not uniform: reports *about* this user describe an account
  //    that no longer exists, so they go; reports they *filed* are evidence about someone
  //    else, so the reporter link is scrubbed and the record kept. The privacy policy has
  //    to say so.
  for (const group of chunk(against.docs, BATCH_LIMIT)) {
    const batch = db.batch();
    group.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
  for (const group of chunk(filed.docs, BATCH_LIMIT)) {
    const batch = db.batch();
    group.forEach((doc) => batch.update(doc.ref, { reporterUID: "deleted-user" }));
    await batch.commit();
  }
  console.log(`   ✅ ${against.size} report(s) deleted, ${filed.size} anonymised`);

  // 7. Username claims.
  for (const group of chunk(names.docs, BATCH_LIMIT)) {
    const batch = db.batch();
    group.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
  console.log(`   ✅ ${names.size} username claim(s) released`);
  console.log(`🗑️ wipeUserData complete for ${uid}`);
}

/**
 * Deletes every trace of the caller's account, then the Auth user itself.
 *
 * Callable rather than relying on `onAuthUserDeleted` alone on purpose: the client needs
 * to know whether the wipe actually succeeded before it clears local data, and a
 * background trigger gives it nothing to wait on.
 *
 * Idempotent — a client retry after a network failure is safe.
 */
export const deleteAccountData = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in to delete your account.");
  }

  await wipeUserData(uid);

  // The Auth user, last. Everything above is retryable while this still exists.
  // Already-deleted is success, not an error — that's what makes a retry safe.
  try {
    await admin.auth().deleteUser(uid);
    console.log("   ✅ Auth user deleted");
  } catch (err) {
    const code = (err as { code?: string }).code;
    if (code !== "auth/user-not-found") throw err;
    console.log("   ✅ Auth user already gone");
  }
  return { ok: true };
});

/**
 * The safety net: whenever an Auth user is deleted **by any route**, its data goes too.
 *
 * In-app deletion is only one way an account disappears. The others — deleting users in
 * the Firebase console, Firebase's own cleanup of old anonymous accounts, and the app
 * deleting a guest after it signs into an existing account — used to leave the user's
 * documents, Storage files and Global posts behind with nobody able to remove them:
 * posts kept appearing in the World feed from an account that no longer existed.
 *
 * A v1 trigger because v2 has no Auth delete event (only blocking beforeCreate /
 * beforeSignIn). After a `deleteAccountData`, this runs again over already-empty paths,
 * which is cheap and harmless.
 */
export const onAuthUserDeleted = functionsV1
  .region(REGION)
  .auth.user()
  .onDelete(async (user) => {
    try {
      await wipeUserData(user.uid);
    } catch (err) {
      // Logged rather than retried: a missing index or permissions problem would fail
      // every retry the same way, and the log is where it gets noticed.
      console.error(`❌ onAuthUserDeleted wipe failed for ${user.uid}:`, err);
    }
  });

/**
 * Retires the anonymous guest a person was using before they signed into an existing
 * account, so guest and account become one.
 *
 * When an Apple or Google ID already has a TodayI account, Firebase can't upgrade the
 * guest in place: the app signs into that account instead, and the guest is left behind.
 * The app used to delete it with `User.delete()` from the client, wrapped in `try?` — but
 * that needs a recent sign-in, which a guest from days ago doesn't have, so it failed
 * silently and guests (with their user documents) accumulated.
 *
 * The app passes the guest's ID token, taken while the guest was still signed in. That
 * token is the proof of control: it is verified here, must belong to an **anonymous**
 * user, and must not be the caller's own account. The guest's on-device memories have
 * already been handed to the account by the app, so its server data is wiped and the Auth
 * user deleted.
 */
export const retireGuestAccount = onCall({ region: REGION }, async (request) => {
  const callerUID = request.auth?.uid;
  if (!callerUID) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const guestToken = (request.data as { guestToken?: unknown })?.guestToken;
  if (typeof guestToken !== "string" || guestToken.length === 0) {
    throw new HttpsError("invalid-argument", "Missing guest token.");
  }

  let decoded: admin.auth.DecodedIdToken;
  try {
    decoded = await admin.auth().verifyIdToken(guestToken);
  } catch {
    throw new HttpsError("permission-denied", "That guest session can't be verified.");
  }
  if (decoded.firebase?.sign_in_provider !== "anonymous") {
    throw new HttpsError("permission-denied", "Only a guest account can be retired this way.");
  }
  if (decoded.uid === callerUID) {
    throw new HttpsError("failed-precondition", "That guest is the signed-in account.");
  }

  await wipeUserData(decoded.uid);
  try {
    await admin.auth().deleteUser(decoded.uid);
  } catch (err) {
    const code = (err as { code?: string }).code;
    if (code !== "auth/user-not-found") throw err;
  }
  console.log(`👋 Retired guest ${decoded.uid} into ${callerUID}`);
  return { ok: true };
});
