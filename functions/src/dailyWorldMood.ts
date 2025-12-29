// src/dailyWorldMood.ts
import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";

// Whole-hour UTC offsets we’ll support
const OFFSETS = [
  -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
    0,   1,   2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14
];

// Helpers
function dayKeyForOffset(nowUtc: Date, offsetHours: number): string {
  const shifted = new Date(nowUtc.getTime() + offsetHours * 60 * 60 * 1000);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, "0");
  const d = String(shifted.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

async function fetchDominantMood(dayKey: string): Promise<string | null> {
  const snap = await admin.firestore().collection("moods").doc(dayKey).get();
  const data = snap.data();
  const tally = data?.tally as Record<string, number> | undefined;

  if (!tally || Object.keys(tally).length === 0) return null;

  let bestMood: string | null = null;
  let bestVal = -Infinity;

  for (const [mood, val] of Object.entries(tally)) {
    if (typeof val === "number" && val > bestVal) {
      bestVal = val;
      bestMood = mood;
    }
  }

  return bestMood;
}

function buildBody(dominantMood: string | null): string {
  if (!dominantMood) {
    return "How did the world feel today? Join the discussion";
  }
  return `The world today felt ${dominantMood} the most — join the discussion`;
}

// Runs hourly, sends only when a zone's local hour == 18 (6PM)
export const dailyWorldMood = onSchedule(
  {
    schedule: "0 * * * *", // every hour, on the hour
    timeZone: "UTC",
    region: "asia-southeast1",
  },
  async () => {
    const now = new Date();
    const utcHour = now.getUTCHours();

    // 🎯 6PM local time
    const TARGET_LOCAL_HOUR = 18;

    const due = OFFSETS.filter(
      off => ((utcHour + off + 24) % 24) === TARGET_LOCAL_HOUR
    );

    if (due.length === 0) return;

    console.log(
      `🌍 UTC ${utcHour}:00 → world mood offsets: ${due.join(",")} (target 18)`
    );

    const sends = due.map(async (off) => {
      const sign = off >= 0 ? "p" : "m";
      const absH = Math.abs(off).toString().padStart(2, "0");

      // New topic namespace
      const topic = `worldmood_6pm_tz_${sign}${absH}`;

      const dayKey = dayKeyForOffset(now, off);
      const dominantMood = await fetchDominantMood(dayKey);
      const body = buildBody(dominantMood);

      const message: admin.messaging.Message = {
        topic,
        notification: {
          title: "World Mood",
          body,
        },
        data: {
          type: "daily_world_mood",
          deeplink: "todayi://global-feed",
          dayKey,
          dominantMood: dominantMood ?? "",
        },
        apns: { payload: { aps: { sound: "default" } } },
      };

      console.log(
        `📤 Sending world mood to ${topic} (dayKey=${dayKey}, dominant=${dominantMood ?? "none"})`
      );

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