// src/profilePropagation.ts
//
// Keeps a person's name and photo in step everywhere they appear.
//
// Every memory and comment stores a *copy* of its author's username (and photo URL),
// taken when it was written, so the feed can render without a profile read per row. The
// cost of that copy: renaming yourself changed only your profile, and every earlier post
// and comment kept the old name — a guest who signed in and picked a real username still
// showed as "guest-XXXX" on everything they'd already written.
//
// The client can't fix this alone. It can rewrite its own memory documents, but the rules
// allow no update to a comment after it's posted — the author's own included — so the
// rename has to happen here, with the Admin SDK.

import * as admin from "firebase-admin";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";

const REGION = "asia-southeast1";
const BATCH_LIMIT = 400;

export const onUserProfileUpdated = onDocumentUpdated(
  { region: REGION, document: "users/{uid}" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const uid = event.params.uid;
    const nameChanged = before.username !== after.username && typeof after.username === "string";
    const photoChanged = before.photoURL !== after.photoURL;
    // The user doc changes for many reasons — blocks, the Premium stamp, the admin flag.
    // Only a new name or photo is worth touching every post for.
    if (!nameChanged && !photoChanged) return;

    const db = admin.firestore();
    const [memories, comments] = await Promise.all([
      db.collection("users").doc(uid).collection("memories").get(),
      // Needs the collection-group index on comments.userID — the same one
      // deleteAccountData uses, so it already exists.
      db.collectionGroup("comments").where("userID", "==", uid).get(),
    ]);

    const memoryPatch: Record<string, unknown> = {};
    const commentPatch: Record<string, unknown> = {};
    if (nameChanged) {
      memoryPatch.username = after.username;
      commentPatch.username = after.username;
    }
    if (photoChanged) {
      memoryPatch.remoteProfilePhotoURL = after.photoURL ?? "";
      commentPatch.photoURL = after.photoURL ?? admin.firestore.FieldValue.delete();
    }

    const refs = [
      ...memories.docs.map((d) => ({ ref: d.ref, patch: memoryPatch })),
      ...comments.docs.map((d) => ({ ref: d.ref, patch: commentPatch })),
    ];
    for (let i = 0; i < refs.length; i += BATCH_LIMIT) {
      const batch = db.batch();
      refs.slice(i, i + BATCH_LIMIT).forEach(({ ref, patch }) => batch.update(ref, patch));
      await batch.commit();
    }
    console.log(`✏️ Profile change for ${uid} copied to ${memories.size} memories and ` +
      `${comments.size} comments (name: ${nameChanged}, photo: ${photoChanged})`);
  }
);
