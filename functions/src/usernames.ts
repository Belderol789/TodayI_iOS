// src/usernames.ts
//
// One person per username.
//
// The name used to be written straight onto `users/{uid}` from Settings, with no check
// at all, so two people could both be "Songbibi" — on the feed, in comments, in a report.
// Now every name has a claim document, `usernames/{key}`, holding its owner's uid, and the
// only way to take one is this callable, which checks and claims in a single transaction:
// two people saving the same name at the same moment can't both win.
//
// Keyed by the name, not the uid, because the question is "is this name taken?" — one
// document read — and one small document per name has none of the size or write-rate
// limits a single uid → name map would hit. The client never touches the collection;
// with no rule for it, Firestore denies client reads and writes by default, and the Admin
// SDK here bypasses rules.

import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const REGION = "asia-southeast1";

/** Letters, numbers, dots and underscores, 3–20 long. Keep in step with the app's check. */
const PATTERN = /^[a-z0-9._]{3,20}$/;

/**
 * Names nobody may pick. `guest-…` needs no entry: generated guest names contain a
 * hyphen, which the pattern above already refuses.
 */
const RESERVED = new Set([
  "admin", "administrator", "todayi", "support", "help", "moderator", "mod",
  "official", "staff", "team", "system", "root", "kuzo", "kuzostudios",
]);

/** The case-insensitive key a name is claimed under: "Songbibi" and "songbibi" are one. */
export function usernameKey(name: string): string {
  return name.trim().toLowerCase();
}

/**
 * Words the moderation lists refuse, applied to the pieces of a name ("ugly.n1gger_" →
 * ["ugly", "nigger"]). Whole pieces only, so a name containing an innocent word that
 * happens to include a listed one isn't refused.
 */
async function containsListedWord(key: string): Promise<boolean> {
  const snap = await admin.firestore().collection("config").doc("moderation").get();
  const data = snap.data() ?? {};
  const listed = new Set<string>(
    [...(data.blockedTerms ?? []), ...(data.sensitiveTerms ?? [])]
      .filter((t: unknown): t is string => typeof t === "string")
      .map((t) => t.toLowerCase())
  );
  const deleet = key
    .replace(/0/g, "o").replace(/1/g, "i").replace(/3/g, "e")
    .replace(/4/g, "a").replace(/5/g, "s");
  return deleet.split(/[._\d]+/).filter(Boolean).some((piece) => listed.has(piece));
}

/**
 * Claims `request.data.username` for the caller, releases their previous name, and
 * writes the new one onto their profile (which `onUserProfileUpdated` then copies onto
 * their posts and comments). Returns the name as stored.
 */
export const claimUsername = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");

  const raw = (request.data as { username?: unknown })?.username;
  if (typeof raw !== "string") throw new HttpsError("invalid-argument", "Missing username.");
  const display = raw.trim();
  const key = usernameKey(display);

  if (!PATTERN.test(key)) {
    throw new HttpsError("invalid-argument",
      "Usernames are 3–20 characters: letters, numbers, dots and underscores.");
  }
  if (RESERVED.has(key)) {
    throw new HttpsError("already-exists", "That username is taken.");
  }
  if (await containsListedWord(key)) {
    throw new HttpsError("invalid-argument", "That username isn't allowed. Try another.");
  }

  const db = admin.firestore();
  const claimRef = db.collection("usernames").doc(key);
  const userRef = db.collection("users").doc(uid);

  await db.runTransaction(async (tx) => {
    const [claim, user] = await Promise.all([tx.get(claimRef), tx.get(userRef)]);
    if (claim.exists && claim.get("uid") !== uid) {
      throw new HttpsError("already-exists", "That username is taken.");
    }

    // Names chosen before claims existed have no claim document. Don't hand one out
    // while someone is still visibly using it, exact spelling.
    if (!claim.exists) {
      const legacy = await tx.get(
        db.collection("users").where("username", "==", display).limit(2)
      );
      if (legacy.docs.some((d) => d.id !== uid)) {
        throw new HttpsError("already-exists", "That username is taken.");
      }
    }

    // Release the previous name, if it's ours and different (a change of case keeps
    // the same key, and so the same claim).
    const previous = user.get("username");
    if (typeof previous === "string") {
      const previousKey = usernameKey(previous);
      if (previousKey !== key) {
        const previousRef = db.collection("usernames").doc(previousKey);
        const previousClaim = await tx.get(previousRef);
        if (previousClaim.exists && previousClaim.get("uid") === uid) tx.delete(previousRef);
      }
    }

    tx.set(claimRef, { uid, username: display, claimedAt: FieldValue.serverTimestamp() });
    tx.set(userRef, { username: display, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });

  console.log(`🏷️ ${uid} claimed username "${display}"`);
  return { username: display };
});
