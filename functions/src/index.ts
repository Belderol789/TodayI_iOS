// src/index.ts
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

export { sendDaily8pmByTZ } from "./dailyByTz";
export { dailyWorldMood } from "./dailyWorldMood";
export { onCommentCreated, onMemoryLikesUpdated } from "./socialMilestones";
export { deleteAccountData } from "./deleteAccount";
export { onMemoryDeleted } from "./memoryCleanup";
export { moderatePublicMemory } from "./moderation";