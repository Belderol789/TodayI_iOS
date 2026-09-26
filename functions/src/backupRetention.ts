// src/backupRetention.ts
//
// Retention for lapsed subscribers' cloud backups.
//
// Cloud backup is the Premium feature, so a lapsed subscriber's data can't sit in
// Firestore forever — that's an unbounded cost with no revenue. But deleting someone's
// journal is about the worst thing this app can do, so the policy is deliberately slow
// and loud:
//
//   11 months after Premium last seen → warn, in the notification inbox
//   12 months                         → delete the cloud backup
//
// Two things this deliberately does NOT do:
//
//   - It never touches the device. The local copy is the user's, always, and a lapsed
//     user opening the app still has their journal.
//   - It never blocks *reading* an existing backup. A lapsed subscriber can still
//     restore and export what's already there; they just stop backing up new entries.
//     Charging for ongoing backup is fair. Holding words someone already wrote hostage
//     until they pay again is not.

import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";

const REGION = "asia-southeast1";
const DAY = 24 * 60 * 60 * 1000;
const WARN_AFTER_DAYS = 334;   // ~11 months
const DELETE_AFTER_DAYS = 365; // 12 months

export const pruneLapsedBackups = onSchedule(
  {
    region: REGION,
    // Once a day is plenty for a 12-month window, and keeps invocations negligible.
    schedule: "0 3 * * *",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const warnBefore = new Date(now - WARN_AFTER_DAYS * DAY);
    const deleteBefore = new Date(now - DELETE_AFTER_DAYS * DAY);

    // `premiumLastSeenAt` is stamped by the client whenever it holds a live entitlement.
    // Absent entirely means the user was never Premium, so there's no backup to prune.
    const stale = await db
      .collection("users")
      .where("premiumLastSeenAt", "<", warnBefore)
      .get();

    let warned = 0;
    let purged = 0;

    for (const doc of stale.docs) {
      const lastSeen: FirebaseFirestore.Timestamp | undefined = doc.get("premiumLastSeenAt");
      if (!lastSeen) continue;
      const uid = doc.id;

      if (lastSeen.toDate() < deleteBefore) {
        // Delete the backup — memories and their media — but keep the account, the
        // profile, and the day/mood history the streak is built from. Losing a year of
        // streak on top of the backup would be gratuitous.
        await db.recursiveDelete(db.collection("users").doc(uid).collection("memories"));
        try {
          await admin.storage().bucket()
            .deleteFiles({ prefix: `users/${uid}/memories/`, force: true });
        } catch (err) {
          console.error(`   ❌ storage prune failed for ${uid}:`, err);
        }
        await doc.ref.update({
          premiumLastSeenAt: admin.firestore.FieldValue.delete(),
          backupPrunedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await notify(uid, {
          title: "Your cloud backup has been removed",
          body: "Premium ended a year ago, so your cloud backup has now been deleted. Entries still on your device are untouched.",
        });
        purged++;
      } else if (doc.get("backupWarnedAt") == null) {
        await doc.ref.update({
          backupWarnedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await notify(uid, {
          title: "Your cloud backup expires in a month",
          body: "Premium ended a while ago. In 30 days your cloud backup will be deleted. Entries on your device stay put — resubscribe any time to keep the backup.",
        });
        warned++;
      }
    }

    console.log(`🧹 backup retention — warned ${warned}, purged ${purged}`);
  }
);

async function notify(uid: string, payload: { title: string; body: string }) {
  await admin.firestore()
    .collection("users").doc(uid)
    .collection("notifications").doc()
    .set({
      type: "backup_retention",
      ...payload,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  // Best-effort push on top of the inbox entry. This is exactly the kind of message
  // someone should not discover only by opening the app.
  try {
    await admin.messaging().send({
      topic: `user_${uid}`,
      notification: payload,
    });
  } catch {
    /* inbox entry is the durable half */
  }
}
