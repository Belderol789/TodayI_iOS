// src/socialMilestones.ts
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";

const USERS = "users";
const MEMORIES = "memories";   // users/{ownerId}/memories/{memoryId}
const COMMENTS_TOP = "comments";

const F_COMMENT_CT  = "commentCount";
/** Comments from anyone but the post's author — what comment milestones count. */
const F_OTHERS_CMT  = "othersCommentCount";
const F_LIKE_CT     = "likes";
const F_NOTIF_CMT   = "notifiedCommentMilestones";
const F_NOTIF_LIKE  = "notifiedLikeMilestones";

const COMMENT_MILESTONES = [1, 5, 10];
const LIKE_MILESTONES    = [10, 50, 100];

function memoryRef(ownerId: string, memoryId: string) {
  return admin.firestore().collection(USERS).doc(ownerId)
    .collection(MEMORIES).doc(memoryId);
}

// ✅ Narrow to TopicMessage (minus 'topic') to avoid the union problem
type TopicPayload = Omit<admin.messaging.TopicMessage, "topic">;

async function sendToOwner(ownerUid: string, payload: TopicPayload) {
  const msg: admin.messaging.TopicMessage = {
    topic: `user_${ownerUid}`,
    ...payload,
  };
  return admin.messaging().send(msg);
}

// 1) COMMENTS
export const onCommentCreated = onDocumentCreated(
  {
    region: "asia-southeast1",
    document: `${COMMENTS_TOP}/{memoryId}/comments/{commentId}`,
  },
  async (event) => {
    const { memoryId } = event.params;
    const snap = event.data;
    if (!snap) return;

    // Hub doc provides memory owner
    const hub = await admin.firestore().collection(COMMENTS_TOP).doc(memoryId).get();
    const ownerID = String(hub.get("ownerID") || "");
    if (!ownerID) {
      console.warn(`No ownerID in comments hub for memory ${memoryId}`);
      return;
    }

    const memRef = memoryRef(ownerID, memoryId);
    const authorUid = String(snap.get("userID") || "");
    const fromOwner = authorUid !== "" && authorUid === ownerID;

    // Milestones count only other people's comments. They used to count every comment
    // and skip the owner's afterwards, so an author replying first used up "first
    // comment" without a notification and the next person's comment (number 2) matched
    // nothing. One transaction gives each comment its own exact count, so two arriving
    // together can't both read the same number and skip a milestone.
    const hit = await admin.firestore().runTransaction(async (tx) => {
      const mem = (await tx.get(memRef)).data() || {};
      const patch: Record<string, unknown> = { [F_COMMENT_CT]: FieldValue.increment(1) };
      if (fromOwner) {
        tx.set(memRef, patch, { merge: true });
        return undefined;
      }
      const count = Number(mem[F_OTHERS_CMT] ?? 0) + 1;
      patch[F_OTHERS_CMT] = count;
      const notified: Record<string, boolean> = mem[F_NOTIF_CMT] ?? {};
      const milestone = COMMENT_MILESTONES.find(m => m === count && !notified[String(m)]);
      // A nested map, not a "field.1" key: set() stores dotted keys as literal field
      // names, so the old flag was never found again and never prevented a repeat.
      if (milestone) patch[F_NOTIF_CMT] = { [String(milestone)]: true };
      tx.set(memRef, patch, { merge: true });
      return milestone;
    });
    if (!hit) return;

    // Minimal inbox record (deduped by deterministic ID)
    await admin.firestore()
    .collection("users").doc(ownerID)
    .collection("notifications")
    .doc(`comment_${memoryId}_${hit}`)
    .set({
      type: "comment_milestone",
      postId: memoryId,
      milestone: hit,
      deeplink: `todayi://post/${memoryId}`,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Push
    await sendToOwner(ownerID, {
      notification: {
        title: hit === 1 ? "Your post got its first comment!" : `Your post has ${hit} comments!`,
        body: "Open TodayI to check the conversation.",
      },
      data: {
        type: "comment_milestone",
        postId: memoryId,
        milestone: String(hit),
        deeplink: `todayi://post/${memoryId}`,
      },
      apns: { payload: { aps: { sound: "default" } } },
    });
  }
);

// 2) LIKES
export const onMemoryLikesUpdated = onDocumentUpdated(
  {
    region: "asia-southeast1",
    document: `${USERS}/{ownerId}/${MEMORIES}/{memoryId}`,
  },
  async (event) => {
    const { ownerId, memoryId } = event.params;
    const before = event.data?.before.data();
    const after  = event.data?.after.data();
    if (!before || !after) return;

    const prevLikes = Number(before[F_LIKE_CT] ?? 0);
    const newLikes  = Number(after[F_LIKE_CT] ?? 0);
    if (!(newLikes > prevLikes)) return;

    const notified: Record<string, boolean> = after[F_NOTIF_LIKE] ?? {};
    const hit = LIKE_MILESTONES.find(m => prevLikes < m && newLikes >= m && !notified[String(m)]);
    if (!hit) return;

    const memRef = memoryRef(ownerId, memoryId);
    // Nested map: a "field.10" key in set() becomes a literal field name, which the
    // check above never read, so unliking and re-liking across 10 notified again.
    await memRef.set({ [F_NOTIF_LIKE]: { [String(hit)]: true } }, { merge: true });

    await admin.firestore()
      .collection("users").doc(ownerId)
      .collection("notifications")
      .doc(`like_${memoryId}_${hit}`)
      .set({
        type: "like_milestone",
        postId: memoryId,
        milestone: hit,
        deeplink: `todayi://post/${memoryId}`,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

    await sendToOwner(ownerId, {
      notification: {
        title: `🔥 Your post hit ${hit} likes!`,
        body: "Nice! Come see who liked it.",
      },
      data: {
        type: "like_milestone",
        postId: memoryId,
        milestone: String(hit),
        deeplink: `todayi://post/${memoryId}`,
      },
      apns: { payload: { aps: { sound: "default" } } },
    });
  }
);