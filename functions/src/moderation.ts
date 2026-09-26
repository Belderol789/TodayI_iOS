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
 * The lists, read from `config/moderation` — the same document the client caches through
 * `ModerationList`. One place to edit, and the two layers cannot drift apart.
 *
 * Cached on the warm instance so a busy period doesn't pay a read per post. `refreshMs`
 * bounds how stale that can get: add a term and it takes effect within five minutes
 * without a deploy, which is the whole point of putting the list in Firestore.
 */
type Lists = { hateTerms: string[]; blockedPhrases: string[] };

const FALLBACK: Lists = {
  hateTerms: [],
  blockedPhrases: [
    "kill you", "kill him", "kill her", "kill them",
    "hunt you down", "beat you up", "i will find you",
    "you should die", "hope you die",
  ],
};

let cached: Lists = FALLBACK;
let cachedAt = 0;
const refreshMs = 5 * 60 * 1000;

function clean(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((v): v is string => typeof v === "string")
        .map((v) => v.trim().toLowerCase())
        .filter(Boolean)
    : [];
}

async function lists(): Promise<Lists> {
  if (Date.now() - cachedAt < refreshMs) return cached;
  try {
    const snap = await admin.firestore().collection("config").doc("moderation").get();
    const data = snap.data();
    if (data) {
      cached = {
        hateTerms: clean(data.hateTerms),
        blockedPhrases: clean(data.blockedPhrases).length
          ? clean(data.blockedPhrases)
          : FALLBACK.blockedPhrases,
      };
    }
    cachedAt = Date.now();
  } catch (err) {
    // Keep whatever is cached. Failing open here is right: the alternative is hiding
    // every public post in the app because one Firestore read failed.
    console.error("⚠️ moderation list fetch failed, using cached:", err);
  }
  return cached;
}

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
export function violatesWith(text: string, list: Lists): boolean {
  const haystack = normalise(text);
  if (list.blockedPhrases.some((p) => haystack.includes(p))) return true;
  return list.hateTerms.some((t) => containsWord(t, haystack));
}

/** Convenience wrapper that fetches (or reuses) the current lists. */
export async function violatesFeedPolicy(text: string): Promise<boolean> {
  return violatesWith(text, await lists());
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

    // Only scan when there is something new to scan. This is an onDocumentWritten
    // trigger, so *every* like fires it — `likes` and `likedBy` live on this document.
    // Without this guard a popular public post re-scans its text on every tap, which is
    // pure invocation cost for a result that cannot have changed.
    const prev = event.data?.before?.exists ? event.data.before.data() : undefined;
    const textChanged = !prev || prev.journalText !== data.journalText;
    const becamePublic = prev?.isPublic !== true;
    if (!textChanged && !becamePublic) return;

    const text = String(data.journalText ?? "");
    if (!text || !(await violatesFeedPolicy(text))) return;

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
