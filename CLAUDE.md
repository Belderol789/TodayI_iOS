# TodayI

A daily mood journal that doubles as a small, day-scoped social network. Each day you pick one of
seven moods, write a short entry, optionally attach photos / video / a voice note / a link, and choose
private or public. Public entries appear in a **Global Feed** limited to a single day, with a mood pie
chart of how everyone felt. Over time the app reflects your year back as a mood-tinted calendar,
a dominant-mood summary, and a yearly breakdown.

Design intent worth preserving: there is no follow graph, no profile browsing, and no scroll across
days in the feed. The unit of sharing is a *feeling*, once a day. Keep new features inside that frame.

iOS 26 · SwiftUI · SwiftData · Firebase (Auth, Firestore, Storage, Messaging) · StoreKit 2 ·
Cloud Functions (TypeScript, Node 22, `asia-southeast1`). Bundle `com.kuzostudiosph.TodayI`.

## Build & run

Single scheme `TodayI`, no workspace — dependencies are SPM, resolved by Xcode.

```bash
xcodebuild -project TodayI.xcodeproj -scheme TodayI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Cloud Functions live in `functions/`:

```bash
cd functions && npm run build        # tsc
```

`npm run deploy` ships them; don't run it without being asked. There is no test target and no
function tests — don't claim a change is "verified by tests".

## Layout

Feature folders are numbered to keep Xcode's navigator in flow order, each with
`Models/`, `Views/`, `ViewModels/`, `Utils/` as needed:

`0Tabbar` · `1Auth` · `3Calendar` · `4Memory` · `5Create` · `6GlobalFeed` · `7Comments` ·
`8Home` · `9PremiumPage` · `10Notification`, plus shared `Utils/` and `Extensions/`.

Large types are split across files by concern using extensions, named `Type_Concern.swift` —
`AuthStore` + `AuthStore_Session/_Profile/_Linking/_Updates`,
`MemoryService` + `MemoryService_Likes/_Comment/_Tally/_Delete/_Privacy/_Fetch`,
`SwiftDataManager` + `SwiftData_Memories/_DateModel/_BlockedList`. Follow this when a file grows —
add an extension file rather than extending the base file.

## Architecture

**Local-first, sync in the background.** `SwiftDataManager.savePostPayload` writes to SwiftData and
copies media into the Documents directory *first*, then fires an unawaited `Task` to upload to
Firebase. The UI never waits on the network. Preserve this ordering when touching the create flow.

**Media resolution always prefers local.** `MemoryModel.imageSources`, `videoSource`, `audioSource`,
and `authorProfilePhotoURL` check the on-disk file before falling back to the remote URL. New media
types should follow the same local-then-remote shape.

**DTO ↔ @Model split.** `MemoryDTO` / `DateModelDTO` / `CommentDTO` are the Firestore wire formats;
`MemoryModel` / `DateModel` / `UserModel` / `BlockedUserList` are the SwiftData records.
`MemoryModel.upsert(from:in:)` is the single merge point — route new remote fields through it rather
than mutating models at call sites. Its **insert** branch must keep assigning `dayKey`/`authorTZ`
from the DTO: `init` can only *derive* a key from `date`, and letting that guess stand is what filed
every imported memory under the day it was imported (opening one day showed the whole history).
`SwiftDataManager.repairMismatchedDayKeys()` runs at launch to heal stores written before that fix. `GlobalFeedService` also keeps a hand-written
`decodeDTOManually` fallback for docs that fail `Codable` decoding; keep both paths in sync when
adding a field.

**`MemoryRow` is a social-feed card.** Media is full-bleed — it reaches the card's left and right
edges — while header, caption, link and audio keep `MemoryRow.textInset`. `body` therefore applies
only *vertical* padding and clips to the card's 16pt radius before `premiumMoodCard` (so the photo
follows the corners but the card's shadow isn't clipped). `MediaBlock` owns its own sizing: photos
are an aspect-ratio box (4:5, Instagram's tallest portrait), never a fixed pixel height, and multiple
photos are a paged `TabView` with a counter and dots. Don't reintroduce fixed media heights or the
old negative-horizontal-padding bleed hack.

**Navigation** is a custom tab bar, not `TabView`. `RootView` switches on the `AppTab` enum inside a
`ZStack`. `auth.hideTabBar` is the global escape hatch for full-screen surfaces (comment thread);
set it on appear, clear it on disappear.

**The World feed is loaded once per launch.** `RootView` owns `GlobalFeedViewModel` so the model
survives tab switches — it used to be a `@StateObject` inside `GlobalFeedView`, and since the custom
tab bar tears down non-selected tabs, every visit rebuilt it and re-read a 30-document page plus the
mood tally. `.task` calls `loadIfNeeded()`, which returns early unless the feed is empty or the
calendar day rolled over; pull-to-refresh and `loadMore` still go to the network deliberately. The
notification inbox follows the same idea: one snapshot listener, no redundant one-shot fetch, and
the unread filter applied in memory.

**Date syncing is once per launch.** `SwiftDataManager.needsDateSync` / `markDatesSynced()` gate a
single `fetchDates` per launch, shared by Home and Calendar — whichever appears first pays for it.
This was once per *install* (callers checked "do we have any `DateModel`"), which meant a day added
after the first sync — or on another device — never appeared on the calendar at all.
`importDatesIfNeeded` also refreshes an existing day's moods now instead of skipping it.

**Dependency passing:** `EntitlementStore`, `AuthStore`, `IAPStore` are `@EnvironmentObject`;
`SwiftDataManager` comes through the custom `\.swiftDataManager` environment key (optional — unwrap it).

**SwiftData migrations** go through `AppSchema.swift`, which carries the recipe for adding
`AppSchemaV2` and a `MigrationStage`.

Adding a property needs no migration work — this was tested directly on 2026-09-17 by building
`dc74a61` (before `AppSchema.swift` existed and before the audio fields), generating a store with
it, and opening that store with current HEAD. Optional, defaulted, and plain non-optional
properties all back-filled, and adopting a `VersionedSchema` over a store written without one
migrated cleanly too. **So `loadIssueModelContainer` is not evidence of a schema problem** — it was
seen once in Sept 2026 while the Mac was down to 1.6 GB free, and low disk, file protection or a
corrupted store are the things to check. Corrupting a store file reproduces that exact error
(`loadIssueModelContainer`, `_explanation: nil`) verbatim, which schema changes never did.
Don't "fix" it by reshaping the models.

That fallback is silent to the user and loses everything written that session, so
`TodayIApp.init` buffers the error through `StartupDiagnostics` and `AppDelegate` flushes it to
Crashlytics as a non-fatal right after `FirebaseApp.configure()` — Firebase does not exist yet at
container-build time, which is why it is buffered rather than recorded inline. If the container fails to
open, `TodayIApp.init` falls back to in-memory and deliberately leaves the on-disk store intact for
recovery — do not "fix" that by deleting the store.

## Data shape (Firestore)

```
users/{uid}                          profile, isRestricted
users/{uid}/memories/{memoryId}      the memory doc (isPublic, dayKey, authorTZ, likes, likedBy…)
users/{uid}/dates/{dayKey}           per-day mood list for the calendar
moods/{dayKey}                       global tally { tally: { Happy: n, … } }
comments/{memoryId}                  hub doc, holds ownerID
comments/{memoryId}/comments/{id}    the comments
reports/{id}                         moderation reports
```

The global feed is a **collection-group query** on `memories` filtered by `isPublic` + `dayKey`.
Any new feed filter needs a matching composite index in the Firebase console.

Security rules live in the Firebase console and are **not** in this repo, so you cannot read or
change them from here. They are strict and hand-written per path — adding a new collection, or a new
client write to an existing one, needs a matching rule added in the console. Flag that explicitly
rather than assuming a write will land.

Current rules, summarized:

| Path | Client access |
|---|---|
| `users/{uid}` | owner read/write; **any signed-in user may add only themselves** to `blockedUsers` (the reciprocal half of a block) |
| `users/{uid}/memories/{id}` | owner full; **anyone can read when `isPublic == true`** via `match /{path=**}/memories/{id}`; any signed-in user may toggle a like on a public memory (`likeToggleOnly()` — only `likes`+`likedBy`, only themselves, ±1) |
| `users/{uid}/dates/{dayKey}` | owner full |
| `users/{uid}/notifications/{id}` | owner read + delete (delete is required by `deleteAccount()`); update only if the sole changed key is `read` → `true`. **No client create** — the Admin SDK writes these |
| `moods/{dayKey}` | any signed-in user may read/create/update |
| `comments/{memoryId}` | public read; signed-in create/update |
| `comments/{memoryId}/comments/{id}` | public read; create requires `userID == auth.uid` and `0 < text.size() <= 1000`; delete only your own |
| `trialDevices/{deviceId}` | any signed-in user (anonymous included) |
| `reports/{id}` | write-only drop box: signed-in create as yourself; **no client read, update or delete** |

**Writes are batched where they belong together.** `postMemory` commits the memory, its
`dates/{dayKey}` entry, the `moods/{dayKey}` tally and the `comments/{memoryId}` hub as one
`WriteBatch` — four round trips and a read became one round trip, and a post can no longer half-land.
`CommentThreadViewModel.postComment` likewise batches the comment and the hub counter (three round
trips → one). Two things to preserve when touching these:

- The mood tally uses a **nested map** (`"tally": [mood: increment(1)]`), not a dotted
  `"tally.happy"` key. `setData` treats dots as literal characters in a field name — only
  `updateData` reads them as paths — and `updateData` would fail on a day with no document yet.
  The merged nested map creates or increments, which is why no read is needed.
- A batch is atomic, so a rule denying **any** write fails the whole post. All four paths are
  permitted today; adding a fifth write means checking its rule first.

Cloud Functions use `firebase-admin` and **bypass rules entirely** — `socialMilestones.ts` writing
`commentCount`, `likes` and notification docs is unaffected by any of the above.

**Storage rules are effectively bypassed for reads.** The rule is owner-only, but
`FirebaseStorageManager` returns `ref.downloadURL()` — a tokened
`firebasestorage.googleapis.com/...?token=` URL that ignores Storage rules. That is why global-feed
images, video, audio and profile photos load for everyone. The consequence: those URLs are readable
by anyone who has the link, indefinitely, and the owner-only rule is not protecting them. Uploads
are still correctly owner-scoped under `users/{uid}/...`.


## Timezones — read before touching dates or notifications

Every memory carries `authorTZ` and a **local** `dayKey` (`Date.formattedDayKeyLocal()`), never UTC.

**`dayKey` must derive from the memory's own date, never from `Date()`.** It is computed once in
`MemoryModel.init` / `MemoryDTO.init(payload:day:)` from the `date`/`day` passed in; `postMemory` and
`incrementDailyMoodTally` then read `memory.dayKey` rather than recomputing. All four recomputed from
"now" until Sept 2026, so a post written after local midnight — or for any past day, which
`savePostPayload(for:)` allows — filed itself under the wrong day and became unfindable by every
dayKey lookup (Home, `MemoryContainer`, the global feed) and stamped the wrong `dates/{dayKey}` and
`moods/{dayKey}` documents.
Both schedulers (`dailyByTz.ts`, `dailyWorldMood.ts`) run hourly at UTC, compute which whole-hour
offsets are currently at the target local hour (20:00 for the journal nudge, 18:00 for the world-mood
nudge), and publish to per-offset FCM topics like `daily8pm_tz_p08` / `worldmood_6pm_tz_m05`.
Clients subscribe to their own offset topic in `NotificationManager`. There is no per-user token
fan-out and no token table — keep it that way. Known limitation: the offset list is whole hours only,
so half-hour zones (India, Nepal) are not covered.

Per-user notifications (comment and like milestones in `socialMilestones.ts`) use the
`user_{uid}` topic instead.

**Every topic subscribe must go through `NotificationManager.enqueueSubscribe`.** FCM rejects
`subscribe(toTopic:)` until an APNs token has reached `Messaging`, failing with code 505 ("No APNS
token specified before fetching FCM Token"). On a cold launch the FCM *registration* token normally
arrives first, so subscribes fired from `didReceiveRegistrationToken` were silently lost with no
retry — `user_{uid}` included, which is the only path for like and comment milestones. The queue
parks topics until `AppDelegate` calls `apnsTokenDidRegister()`, then flushes. Calling
`Messaging.messaging().subscribe` directly reintroduces the bug. Topic keys in `UserDefaults` store
the full topic string and are written only after the server accepts the subscribe.

## Auth

Anonymous by default — first launch creates a Firebase anonymous user with a `guest-XXXX` username
and journaling works immediately. Sign-in (Google, email) is gated **only** in front of public
posting, via `AuthRequiredView`. Don't add sign-in walls in front of private journaling. Face ID lock
is opt-in and off by default.

`auth.isRestricted` is an admin-set flag on the user doc that disables public posting; it is set from
the Firebase console, not from the app.

## Premium

StoreKit 2 subscriptions (`IAP.monthlyID` / `IAP.yearlyID`), entitlements cached in Keychain, plus a
device-scoped free trial keyed on a Keychain UUID (`TrialDeviceID`) and validated server-side by
`FirebaseFirestoreManager.activateDeviceTrialIfNeeded()`.

⚠️ **`EntitlementStore.isPremium` is hardcoded `true` on purpose** (see `EntitlementStore.swift:19`,
with the real derivation commented out at ~:39 and ~:174). Everyone is premium for now. This is
intentional — **do not "fix" it**. When it is time to switch on real gating, uncomment those two
lines rather than writing new logic.

The free/premium line, when enabled: free users get one memory per day
(`SwiftData_Memories.loadMemories` returns only `rows.last`), premium gets multiple per day, video and
galleries, feed flair, and a monthly mood summary.

## Moderation

Report reasons in `ReportService`, block list in `BlockedUserList` mirrored to both SwiftData and
Firestore, and blocked/reported authors are filtered out of the feed immediately on the client.

## Conventions

- Two-space indentation, `// MARK: -` section headers.
- `print` with emoji prefixes (`✅ ❌ 📤 ⏰`) is the established logging style in both Swift and TS.
  `LoggerManager.instance.logFirebaseCall()` marks Firestore entry points — keep calling it in new
  service methods.
- Date helpers live in `Extensions/DateExtension.swift` (`today`, `startOfDay(in:)`, `dayBounds(in:)`,
  `formattedDayKeyLocal(in:)`). Use them instead of building `Calendar` math inline.
- Mood colors come from `Mood.adaptiveColor`, which resolves light/dark through `UIColor`. Never
  hardcode a mood color.
- `TestManager` and `GlobalFeedService.generateTestPage` seed fake data for previews; they are dev
  tools, not test infrastructure.

## Gotchas

- The background upload in `savePostPayload` is fire-and-forget with **no retry**. If it fails the
  memory stays local and silently never syncs. Worth knowing before debugging "missing" posts.
- `GoogleService-Info.plist` is committed to the repo.

## Rules history

The five client/rule mismatches found in Sept 2026 — likes on other people's posts, account
deletion blocked on `notifications` delete, `reports` having no rule at all, the reciprocal half of
a block being a denied cross-user write, and uncapped comment length — were all resolved by the
ruleset deployed 2026-09-17 plus the client-side comment cap. The table above reflects that
ruleset. Rules live in the console, so confirm there before trusting this summary.
