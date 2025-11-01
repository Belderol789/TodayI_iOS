// src/index.ts
import * as admin from "firebase-admin";
admin.initializeApp();

export { sendDaily8pmByTZ } from "./dailyByTz";
export { onCommentCreated, onMemoryLikesUpdated } from "./socialMilestones";