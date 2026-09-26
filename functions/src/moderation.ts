// src/moderation.ts
//
// The enforcing half of the content filter.
//
// `ContentModeration.swift` runs the same categories while someone is typing, which is
// good for feedback and worthless as a control — it ships inside the binary and only
// runs if the client chooses to. This runs on write, server-side, and cannot be skipped
// by an old build, a patched client, or a direct Firestore call.
//
// Scope is deliberately narrow: **public memories only**. A private entry is a diary
// page, and scanning it would betray the premise of the app for no safety gain, since
// nobody else can read it.

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

const REGION = "asia-southeast1";

/**
 * Slurs and dehumanising terms. Intentionally empty in the repo.
 *
 * A slur list is a live content decision with real costs in both directions, and it
 * belongs in a maintained source (a vendor feed, or Shutterstock's
 * List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) rather than in application
 * code written once and forgotten. Populate it here — a functions deploy updates it
 * without an App Store release, which is the main reason enforcement lives server-side.
 */
const HATE_TERMS: string[] = [];

/** Threats aimed at another person. Phrases, so ordinary venting doesn't match. */
const VIOLENT_PHRASES = [
  "kill you", "kill him", "kill her", "kill them",
  "hunt you down", "beat you up", "i will find you",
  "you should die", "hope you die",
];

/**
 * Mirrors `ContentModeration.normalise` — lowercase, strip accents, undo leetspeak,
 * collapse whitespace. Keep the two in step or the client will pass text the server
 * then rejects, which reads to the user as a random failure.
 */
function normalise(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/0/g, "o")
    .replace(/1/g, "i")
    .replace(/3/g, "e")
    .replace(/4/g, "a")
    .replace(/5/g, "s")
    .replace(/@/g, "a")
    .replace(/\$/g, "s")
    .replace(/\s+/g, " ");
}

/** Whole-word match, so an innocent word containing a term isn't caught. */
function containsWord(term: string, haystack: string): boolean {
  const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`\\b${escaped}\\b`).test(haystack);
}

/** True when this text may not appear in the Global feed. */
export function violatesFeedPolicy(text: string): boolean {
  const haystack = normalise(text);
  if (VIOLENT_PHRASES.some((p) => haystack.includes(p))) return true;
  return HATE_TERMS.some((t) => containsWord(t, haystack));
}

export const moderatePublicMemory = onDocumentWritten(
  {
    region: REGION,
    document: "users/{uid}/memories/{memoryId}",
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;

    const data = after.data();
    if (!data?.isPublic) return;           // private entries are never scanned
    if (data.moderationHidden === true) return; // already handled; also stops the write loop

    const text = String(data.journalText ?? "");
    if (!text || !violatesFeedPolicy(text)) return;

    const { uid, memoryId } = event.params;
    console.log(`🚫 hiding public memory ${memoryId} from ${uid} — feed policy`);

    // Hide it from the feed rather than deleting it. The entry is still the author's
    // journal and destroying their writing is not ours to do; it just stops being public.
    await after.ref.update({
      isPublic: false,
      moderationHidden: true,
      moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Tell them, in the existing inbox. A post that silently vanishes reads as a bug and
    // teaches nothing; an explanation is the only part of this with any corrective value.
    await admin
      .firestore()
      .collection("users").doc(uid)
      .collection("notifications").doc()
      .set({
        type: "moderation",
        title: "A post was made Personal",
        body: "One of your posts didn't meet the Global feed guidelines, so it's now visible only to you. Your entry hasn't been changed or deleted.",
        memoryID: memoryId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  }
);
