// src/index.ts
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

export { sendDaily8pmByTZ } from "./dailyByTz";
export { dailyWorldMood } from "./dailyWorldMood";
export { onCommentCreated, onMemoryLikesUpdated } from "./socialMilestones";