// src/socialMilestones.ts
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";

const USERS = "users";
const MEMORIES = "memories";   // users/{ownerId}/memories/{memoryId}
const COMMENTS_TOP = "comments";

const F_COMMENT_CT  = "commentCount";
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

    // Increment comment count and read updated doc
    await memRef.set({ [F_COMMENT_CT]: FieldValue.increment(1) }, { merge: true });
    const mem = (await memRef.get()).data() || {};
    const count = Number(mem[F_COMMENT_CT] ?? 0);
    const notified: Record<string, boolean> = mem[F_NOTIF_CMT] ?? {};

    const hit = COMMENT_MILESTONES.find(m => m === count && !notified[String(m)]);
    if (!hit) return;

    // Optional: ignore owner’s own comment
    const authorUid = String(snap.get("userID") || "");
    if (authorUid && authorUid === ownerID) return;

    // Mark as notified (idempotent)
    await memRef.set({ [`${F_NOTIF_CMT}.${hit}`]: true }, { merge: true });

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
    await memRef.set({ [`${F_NOTIF_LIKE}.${hit}`]: true }, { merge: true });

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