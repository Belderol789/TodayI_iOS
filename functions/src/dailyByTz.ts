// src/dailyByTz.ts
import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";

// Whole-hour UTC offsets we’ll support
const OFFSETS = [
  -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
    0,   1,   2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14
];

// Runs every minute, sends only when a zone's local hour == target
export const sendDaily8pmByTZ = onSchedule(
  {
    schedule: "* * * * *",      // every minute
    timeZone: "UTC",
    region: "asia-southeast1",
  },
  async () => {
    const now = new Date();
    const utcHour = now.getUTCHours();
    const utcMinute = now.getUTCMinutes();

    // Only at the top of the hour
    if (utcMinute !== 0) return;

    // Default 20 (8PM). Override with: export TARGET_LOCAL_HOUR=23 (etc.)
    const TARGET_LOCAL_HOUR = Number(process.env.TARGET_LOCAL_HOUR ?? 20);

    // Which offsets are at that local hour right now?
    const due = OFFSETS.filter(off => ((utcHour + off + 24) % 24) === TARGET_LOCAL_HOUR);
    if (due.length === 0) return;

    console.log(`⏰ UTC ${utcHour}:00 → sending to offsets: ${due.join(",")} (target ${TARGET_LOCAL_HOUR})`);

    const sends = due.map(off => {
      const sign = off >= 0 ? "p" : "m";
      const absH = Math.abs(off).toString().padStart(2, "0");
      const topic = `daily8pm_tz_${sign}${absH}`; // e.g., daily8pm_tz_p08

      const message: admin.messaging.Message = {
        topic,
        notification: {
          title: "How was your day?",
          body:  "Log a quick memory in TodayI.",
        },
        data: {
          type: "daily_journal_prompt",
          deeplink: "todayi://new-memory",
        },
        apns: { payload: { aps: { sound: "default" } } },
      };

      console.log(`📤 Sending to ${topic}`);
      return admin.messaging().send(message);
    });

    const results = await Promise.allSettled(sends);
    results.forEach((r, i) => {
      const off = due[i];
      if (r.status === "fulfilled") console.log(`✅ OK offset ${off}`);
      else console.error(`❌ FAIL offset ${off}`, r.reason);
    });
  }
);