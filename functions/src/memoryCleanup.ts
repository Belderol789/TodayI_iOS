// src/memoryCleanup.ts
//
// Comment threads outlive the posts they belong to unless something deletes them.
//
// `comments/{memoryId}` is a top-level collection, so deleting a memory never touched it.
// The client can't clean it up either: rules grant no delete on the hub at all, and only
// permit deleting your *own* replies — so a thread containing other people's comments is
// unreachable from the app by design. The Admin SDK isn't bound by that.
//
// Before this, deleting a post left the entire conversation about it in Firestore
// permanently, including everyone's usernames.

import * as admin from "firebase-admin";
import { onDocumentDeleted } from "firebase-functions/v2/firestore";

const REGION = "asia-southeast1";

export const onMemoryDeleted = onDocumentDeleted(
  {
    region: REGION,
    document: "users/{uid}/memories/{memoryId}",
  },
  async (event) => {
    const { memoryId } = event.params;
    const hub = admin.firestore().collection("comments").doc(memoryId);

    // recursiveDelete removes the hub and its comments subcollection together, and is a
    // no-op when the thread never existed — which is the common case, since most memories
    // are private and never accumulate comments.
    await admin.firestore().recursiveDelete(hub);
    console.log(`🗑️ comment thread cleaned up for memory ${memoryId}`);
  }
);
