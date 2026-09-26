// src/reportAlerts.ts
//
// Tells you when someone files a report.
//
// `reports` is a write-only drop box — the rules grant no client read, so nothing in the
// app can show them and nothing was telling anyone they existed. They were visible only
// to whoever remembered to open the Firestore console.
//
// That matters more than it sounds: reports are the moderation strategy, and App Review
// expects UGC reports to be acted on promptly. A queue nobody is notified about isn't a
// moderation system, it's a folder.
//
// Reuses the FCM topic plumbing already in the app rather than adding an email provider.
// Subscribe your own device to `admin_reports` to receive these.

import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

const REGION = "asia-southeast1";
export const ADMIN_TOPIC = "admin_reports";

export const onReportCreated = onDocumentCreated(
  { region: REGION, document: "reports/{reportId}" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const reason = String(snap.get("reason") ?? "Unknown");
    const reportedUID = String(snap.get("reportedUID") ?? "");
    const memoryID = String(snap.get("memoryID") ?? "");

    try {
      await admin.messaging().send({
        topic: ADMIN_TOPIC,
        notification: {
          title: `New report: ${reason}`,
          // Enough to triage from the lock screen without opening the console.
          body: `User ${reportedUID.slice(0, 8)}… · memory ${memoryID.slice(0, 8)}…`,
        },
        data: {
          type: "report",
          reportId: event.params.reportId,
          reportedUID,
          memoryID,
        },
      });
      console.log(`🚩 report alert sent — ${reason}`);
    } catch (err) {
      // Never let a failed alert fail the report write; the document is what matters.
      console.error("❌ report alert failed:", err);
    }
  }
);
