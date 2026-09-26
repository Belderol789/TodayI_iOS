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

**But "local" is a lie for anything that came from the cloud.** `MemoryModel.upsert`'s *insert*
branch sets `localImageNames: []` / `videoLocalPath: nil`, so a memory restored after a reinstall,
synced from another device, or seen in the Global feed has **no on-disk copy at all** — the fallback
to remote hides that completely, and everything looks normal until something removes the remote
copy. That is exactly how "Remove from Cloud Only" destroyed the only copy of a photo while the
text survived (the text was in SwiftData all along).

`MemoryService.materializeLocally(_:)` pulls the media down and fills those fields in.
`deleteMemory(scope: .remoteOnly)` calls it **first** and throws `couldNotKeepLocalCopy` rather than
proceeding, so the dialog's promise is true before anything is deleted. Any new feature that removes
a remote copy while claiming the local one survives must do the same.

`deleteMemory(scope: .everywhere)` calls `removeLocalFiles(_:)` — without it, deleting a memory left
its photos in `Documents/` forever with nothing referencing them.

Known consequence, not yet addressed: after a restore, media is served from Storage on every view
rather than from disk, so a reinstalled premium user quietly pays egress for their own back
catalogue. `ProtectedMediaStore` self-heals this for Personal entries (it caches to disk on first
fetch); public media does not.

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

**The World feed is loaded once per launch.** `RootView` owns `GlobalFeedViewModel` and injects it as
an `@EnvironmentObject` so the model survives tab switches — it used to be a `@StateObject` inside
`GlobalFeedView`, and since the custom tab bar tears down non-selected tabs, every visit rebuilt it
and re-read a 30-document page plus the mood tally. `CreateMemoryView` reads the same object: posting
a **public** memory skips the preview modal, calls `prepend(_:)` and switches to the Global tab, so
the post is already on top when the tab appears. That is local on purpose — the upload is
fire-and-forget so the document may not exist server-side yet, and `fetchPublicMemories` has **no
`order(by:)`**, so rows come back in document-ID (UUID) order and a re-fetch wouldn't put it first
anyway. `justPosted` is re-merged after every refresh until the server returns the row. Ordering the
feed by `createdAt` would need a composite index on (`isPublic`, `dayKey`, `createdAt`) in the
console. A **private** post still shows the preview modal. `.task` calls `loadIfNeeded()`, which returns early unless the feed is empty or the
calendar day rolled over; pull-to-refresh and `loadMore` still go to the network deliberately. The
notification inbox follows the same idea: one snapshot listener, no redundant one-shot fetch, and
the unread filter applied in memory.

**The streak is computed from `DateModel`, never gated.** `SwiftDataManager.currentStreak()` counts
back over the one-row-per-journaled-day table, which is written on every local save and refilled from
Firestore once per launch — so the flame costs zero reads and survives a reinstall. Today being
missing does *not* break the run (the day isn't over); it renders hollow and muted as the nudge, and
fills once today is written. The pill is shown **at zero too** — hiding it meant a new user never
discovered the mechanic — as a plain `0`, with a caption under the header. It and the Profile button
are `.fixedSize()` and the title flexes, so a wider label can't wrap "Today's Memory" onto two lines. `HomeView` computes it before any network await so it paints
immediately, then again after the imports. It is deliberately free: a paywalled streak would work
against the retention it exists to create.

**The widget reads a snapshot, not the store.** `TodayIWidget` is a separate process and can only
reach an App Group container, so rather than migrating the SwiftData store into one — a real
migration on a shipped app whose container has already failed to open once — the app publishes a
handful of plain values (`streak.*` and `world.*`) into
`UserDefaults(suiteName: "group.com.kuzostudiosph.TodayI")`.
`SwiftDataManager.refreshStreakSnapshot()` computes and publishes in one step and is the only thing
callers should use; it also calls `WidgetCenter.reloadTimelines`. The contract is **duplicated** in
`TodayIWidget/StreakSnapshotReader.swift` because sharing one file across two synchronised folder
groups means hand-editing the Xcode project — three string literals are cheaper to keep in step than
a corrupted `project.pbxproj`, but they must be kept in step, along with
`StreakSnapshot.widgetKind` ↔ `TodayIWidget.kind`. Entitlements are committed for both targets;
**device and TestFlight builds also need App Groups ticked in Signing & Capabilities** so the
provisioning profile carries it. Simulator works without.

**The widget's world mood is a hand-me-down, not a fetch.** The extension has no Firebase and a
tight memory budget, so `GlobalFeedViewModel.updateGlobalTally` publishes the dominant mood it has
*already* fetched via `StreakSnapshot.writeWorldMood` — zero extra reads. The cost is staleness: it
is only as fresh as the last World feed load (once per launch, or a pull-to-refresh). `world.updatedAt`
is published so `WorldMood.isFresh` can decline to render a mood from yesterday, which is the whole
point — a day-old "the world feels Happy" is a small lie, and the widget shows the streak alone
instead. Colours are published as **resolved light and dark hex**, not a mood name, so the widget
renders what it is given and `Mood.adaptiveColor` stays the single source for the palette.

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

**A download token is minted only for Global media.** `ref.downloadURL()` returns a tokened
`firebasestorage.googleapis.com/...?token=` URL, and that token **bypasses Storage rules entirely** —
which is why global-feed media loads for everyone despite an owner-only rule. For a public post
that's the feature. For a Personal entry it was simply wrong: its photos stayed world-readable by
anyone holding the link, forever, and toggling a post back to Personal didn't un-share it.

So uploads are privacy-aware. `FirebaseStorageManager.RemoteMediaRef` is either a `publicURL`
(tokened, Global) or a `protectedPath` (a bare `users/{uid}/…` path, Personal), and the same field
on the model and DTO holds either form — `isPublicRef(_:)` tells them apart. Protected media is
fetched through `ProtectedMediaStore`, which uses the authenticated SDK so the owner-only rule
actually applies, and caches to `Documents/protected/`. **`URL(string:)` parses a bare path into a
valid relative URL**, so the form must be checked explicitly or private media silently renders as a
broken remote image — that is why `imageSources` branches on `isPublicRef` rather than on
`URL.init?`.

`updatePrivacy(for:isPublic:)` converts the media *before* writing the flag: Global mints a token,
Personal **revokes** it by clearing `firebaseStorageDownloadTokens`, which invalidates every link
already handed out. The plain `updatePrivacy(userID:memoryID:)` overload only flips the flag — use
the model overload for anything user-facing.

There is no migration for media uploaded before this existed — Firestore and Storage were wiped
2026-09-26, so every object in the bucket was written by the privacy-aware path. If that ever stops
being true, the fix is a token sweep with the Admin SDK, **not** an admin-gated client callable: the
owner can write their own user document, so any `admin: true` flag the client can set is an
escalation route rather than a permission check.

Uploads remain owner-scoped under `users/{uid}/...` either way.


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
parks topics until `AppDelegate` calls `apnsTokenDidRegister()`, then flushes. **Unsubscribe needs
the token too** — `enqueueUnsubscribe` exists for that reason; calling
`Messaging.messaging().subscribe`/`unsubscribe` directly reintroduces the bug.

Equally important: `AppDelegate` calls `registerForRemoteNotificationsIfAuthorized()` on **every**
launch. `registerForRemoteNotifications()` used to be reachable only from `configure()`, which only
runs from the first-post prompt — so for anyone who had already granted permission no APNs token
ever arrived again, the queue never flushed, and push silently stopped working. A launch log showing
`⏳ Queued …` with no `📡 APNs ready` is that failure. Topic keys in `UserDefaults` store
the full topic string and are written only after the server accepts the subscribe.

**The daily nudge carries mood buttons.** `NotificationManager_Actions.swift` registers the
`DAILY_CHECKIN` category — three moods plus "Something else…", because iOS shows only about four
actions. Tapping a mood writes a **private, mood-only** memory for today without foregrounding the
app, and posts `.memoryDidChangeLocally` so Home refreshes its card and streak; without that the UI
keeps insisting today is empty. Two constraints hold this together:

- The handler reads the uid from `Auth.auth().currentUser`, not `AuthStore`. A notification action
  can launch the app into the background where no SwiftUI scene — and therefore no `AuthStore` —
  ever exists. `AppServices` bridges the delegate to `SwiftDataManager`/`EntitlementStore`, and only
  Firebase-free stores may go in it: `AuthStore.init` builds a Firestore handle, so constructing it
  during `TodayIApp.init` crashes with `FIRIllegalStateException` before `FirebaseApp.configure()`
  runs. `_authStore = StateObject(wrappedValue:)` takes an **autoclosure** and must stay one.
- The push must carry `apns.payload.aps.category = "DAILY_CHECKIN"` (see `dailyByTz.ts`) or the
  buttons appear only on the local reminder. **Requires a functions deploy to take effect.**

## Auth

Anonymous by default — first launch creates a Firebase anonymous user with a `guest-XXXX` username
and journaling works immediately. Sign-in (Google, email) is gated **only** in front of public
posting, via `AuthRequiredView`. Don't add sign-in walls in front of private journaling. Face ID lock
is opt-in and off by default.

`auth.isRestricted` is an admin-set flag on the user doc that disables public posting; it is set from
the Firebase console, not from the app.

## Premium

StoreKit 2 subscriptions (`IAP.monthlyID` / `IAP.yearlyID`), entitlements cached in Keychain, plus a
StoreKit introductory offer (see below) as the free-trial mechanism.

There used to also be a device-scoped, no-card trial: `TrialDeviceID` (Keychain UUID) plus
`FirebaseFirestoreManager.activateDeviceTrialIfNeeded()` / `checkDeviceTrialPremium()`, writing to a
`trialDevices` Firestore collection. It was removed 2026-09-26 — `checkDeviceTrialPremium()` had no
caller and was never wired into `EntitlementStore.isPremium`, so it granted nothing; the write side
ran on every launch regardless. It also shared the exact Keychain fragility the account-required-for-
Premium rule exists to fix: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` survives deleting the
app but not a new device or a wiped Keychain. If a no-card trial is wanted again, gate it on a signed-
in identity, not a device ID, and decide deliberately whether it should include cloud backup — that's
the expensive feature to hand out before anyone has proven intent to pay.

The **live** trial mechanism is a StoreKit introductory offer configured in App Store Connect, which
needs no app code beyond disclosure: `Transaction.updates` / `currentEntitlements` already treat a
trial period identically to a paid one, so nothing downstream has to know a trial happened. What the
app still owes the user is telling them *before* they buy — Apple guideline 3.1.2 requires trial terms
disclosed pre-purchase — via `Product.subscription.introductoryOffer` and an
`isEligibleForIntroOffer` check (not yet built).

`EntitlementStore.isPremium` is **derived** from StoreKit entitlements via a single
`recomputeIsPremium(reason:)`, and is `private(set)` — nothing outside the store may assign it. It was
hardcoded `true` through most of 2026 while the paywall was being built; that is over, and gating is
live. For development, a **DEBUG-only** `devForcePremium` (a `UserDefaults`-backed computed property,
compiled out of release) is surfaced as "Force Premium" in Settings → Developer. A real subscription
keeps Premium on regardless of that switch.

The free/premium line: free users get **one memory per day** — the most recent — plus a 300-character
cap and no video or gallery. Premium adds every memory, video, galleries, feed flair and a monthly
mood summary.

**Never hide a user's own data silently.** Free tier used to enforce the one-per-day limit with
`fetchLimit = 1`, so a second memory vanished from `MemoryContainer` while still sitting in SwiftData
and Firestore — indistinguishable from data loss. That screen now loads the whole day and renders a
locked row ("N more memories from this day") that opens Premium. `HomeView` still fetches only the
latest for free users, which is *consistent* rather than hiding: the latest is exactly the one the
free tier can reach.

**Buying Premium requires a real account** (`PremiumView.needsAccount`). This is the one hard
sign-in gate in the app and it is deliberate: everything else works anonymously, but Premium's
headline benefit is cloud backup, and a backup is only as durable as the identity it is filed
under. An anonymous uid lives in the **Keychain** — it survives deleting the app (which is why a
reinstall recovers), but not a new device, a wiped Keychain, or a restore without it. Once it is
gone the backup sits in Firestore under an identity nobody can authenticate as, permanently
unreachable. Letting someone pay first is selling them something that can silently evaporate.

Restore Purchases is **not** gated — Apple requires it to be reachable, and it only touches
StoreKit entitlements, which are Apple-ID scoped rather than account scoped.

Upsell entry points, deliberately few: the Premium pill in the World Feed and Calendar toolbars, the
Create screen's Video/Gallery gates, its "Unlock" button and "Premium removes the limit" line, the
locked-memories row, and a non-blocking notice on Create when today already has a memory. The
Notifications tab deliberately has **no** pill — four entry points for a one-screen product is
already plenty, and the notification inbox is not where value is demonstrated.

## Cost shape

**Storage egress is the bill; Firestore is rounding error.** Modelled against the real code
paths, Firestore is ~8% of spend and Cloud Storage ~90% — because every Global feed viewer
downloads the media of every post they scroll past.

Uploads are therefore **downscaled in `FirebaseStorageManager`** (1440px long edge for feed
photos, 512px for avatars, quality 0.8). They used to be `jpegData(0.85)` on the full-resolution
picker image — ~2.5 MB per photo, more from a 48MP camera — while `MediaBlock` renders in a 4:5
box under 1200px wide, so none of that resolution was ever visible. Don't remove the downscale to
"improve quality"; it is roughly an 8× swing in the monthly bill. **Video is still uploaded
unmodified** and is the remaining large item.

Two read-side notes: `MemoryService.fetchDates` is an **unbounded** `getDocuments()` on
`users/{uid}/dates`, so it grows forever — at one year of history it is ~89% of all reads. It is
cheap today only because reads are cheap. And `moderatePublicMemory` is an `onDocumentWritten`
trigger, so every *like* fires it (`likes`/`likedBy` live on the memory doc); it early-returns
unless `journalText` changed or the post just became public. Keep that guard.

## Maintenance mode

`MaintenanceGate` reads `maintenance_enabled` / `maintenance_message` from **Remote Config** and
`TodayIApp` swaps `RootView` for `MaintenanceView` when set. Remote Config rather than a Firestore
doc: no billed read per launch, no security rule, and a console toggle already built for it.
It refreshes on launch and on every foreground, so the switch takes effect without a relaunch and
releases the same way.

**It fails open, deliberately.** Every failure path — no network, fetch error, malformed value —
leaves the app usable. Locking someone out of their own journal because their train went into a
tunnel would be a worse bug than whatever the switch was guarding.

## Privacy manifest

`TodayI/PrivacyInfo.xcprivacy` and `TodayIWidget/PrivacyInfo.xcprivacy`. Both are required —
an app extension is a separate binary and needs its own — and **App Store Connect rejects an
upload automatically without them**, before a human sees it.

Declare only what *this app* does. Third-party SDKs ship their own manifests (Firebase's are in
the bundle) and Xcode aggregates them into the privacy report at archive time; duplicating
theirs here is wrong, not just redundant.

Verified 2026-09-26 against the code: the only required-reason API used is `UserDefaults`
(`CA92.1` for the app's own prefs, `1C8F.1` for the widget's App Group). No file-timestamp,
disk-space, active-keyboard or boot-time APIs anywhere. **Firebase Analytics is not linked** —
`project.pbxproj` mentions it as a package product, but `nm`/`strings` on the built binary find
nothing, so nothing is auto-collected and there is no `FIREBASE_ANALYTICS_COLLECTION_ENABLED`
to worry about. If Analytics is ever added, this file and the App Store privacy label both
change.

After editing, check it actually ships — a manifest Xcode doesn't copy is worthless:

```bash
find "$(find ~/Library/Developer/Xcode/DerivedData -name TodayI.app | head -1)" -name PrivacyInfo.xcprivacy
```

Expect it at the bundle root **and** inside `PlugIns/TodayIWidgetExtension.appex/`.

## Cloud backup is the Premium feature

Free users keep Personal entries **on device only**; Premium adds the remote copy. A
Global post always uploads regardless of tier — it can't be in the feed otherwise.
`savePostPayload` makes that call; everything not uploaded is flagged
`MemoryModel.needsCloudBackup`.

This is honest pricing (remote storage is a real cost) and a better line than withholding
the user's own data. It is *not* a big cost saving — post-downscale a free user's private
media is a few cents a month across hundreds of users. The 90% cost driver is feed egress,
which this doesn't touch. Don't justify it on cost.

Free users are less exposed than it sounds: **nothing is excluded from iCloud backup**, so
the SwiftData store and `Documents/` ride along in the device backup. A new phone restored
from iCloud keeps everything; only explicitly deleting the app loses it.

**`needsCloudBackup` is also the retry queue.** A failed upload sets it instead of logging
and giving up, which is what made the fire-and-forget upload silently lose memories.
`CloudBackupService.drain` runs on launch and on the `isPremium` transition, oldest-first,
200 at a time, and is guarded by `isRunning` so subscribing during a launch drain can't
upload everything twice. Backfill happens from **disk**, not a `PostPayload` — the
`UIImage`s are long gone by then.

**Three rules this must keep.** They are the whole ethical shape of the feature:

1. **Never block reading an existing backup.** `fetchMemories` / `importMemoriesIfNeeded`
   are deliberately un-gated. Charging for ongoing backup is fair; holding words someone
   already wrote hostage until they pay again is not, and it would invite App Review
   attention. Lapsed users are still subject to the pre-existing free-tier *display* limit
   (latest memory per day, with the locked row) — that's the old product line, not this one.
2. **Never delete without warning.** `pruneLapsedBackups` warns in the inbox at ~11 months
   after `premiumLastSeenAt` and deletes at 12, and it removes only `memories` — the
   profile and the `dates` history the streak is built from survive.
3. **Never touch the device copy.** Retention is a server-side prune of the *backup*. A
   lapsed user opening the app still has their journal.

`premiumLastSeenAt` is stamped by the client, because StoreKit entitlements live on the
device and Firestore has no idea who is subscribed. Forging it only keeps your own backup
alive longer, so it isn't worth defending against. Owner write already covers it — no new
rule needed.

**There is no export feature.** Point 1 above is satisfied by restore, not export; if you
want a real "download my journal" path it still needs building.

## Moderation

**Reports notify you, or they may as well not exist.** `reports` is a write-only drop box with no
client read, so nothing in the app can surface one and nothing did — they were visible only to
whoever remembered to open the Firestore console. `onReportCreated` pushes each one to the
`admin_reports` FCM topic; **subscribe your own device or the queue is still unwatched.** This is the
moderation strategy, and App Review expects UGC reports to be acted on promptly.

Report reasons in `ReportService`, block list in `BlockedUserList` mirrored to both SwiftData and
Firestore, and blocked/reported authors are filtered out of the feed immediately on the client
(`GlobalFeedView` observes `BlockedUserList` via `@Query`, so a block hides the row with no refetch).

**Blocking is mute semantics, not true blocking.** It is enforced entirely on the client: nothing
stops a blocked user reading, liking or commenting on a public post, you simply don't see them.
Their likes still count toward your milestone notifications — those are aggregates (`"your post
reached 10 likes"`) with no actor identity, so nothing about them is *revealed*, but the interaction
is not prevented. Real blocking needs rule changes in the console plus a check in
`socialMilestones.ts`.

**Unblocking must write Firestore, and `syncBlockedUsers` must not merge.** `removeBlockedUser` once
touched only SwiftData while `syncBlockedUsers` unioned the remote list back in on every launch, so
an unblock silently reversed itself the next time the app opened — unblocking was impossible. Remote
is now authoritative on sync; Firestore applies pending offline writes to its own cache, so a block
made offline is already in the list that comes back. Both block writes are `await`ed now: they were
bare `setData` calls with no error handling, so a denied write left a device-only block that vanished
on reinstall. The reciprocal *removal* is best-effort — the rule permits adding yourself to someone
else's `blockedUsers` and may not permit removing yourself. **Confirm that in the console.**

**Content filtering is two layers, and the tiers are a product decision.**
`ContentModeration.swift` runs while the user types (fast, bypassable, feedback only);
`functions/src/moderation.ts` re-runs the same categories on write and is what actually enforces.
Keep `normalise()` identical in both or the client will pass text the server then rejects.

- **Violent threats** block a *public* post only. The entry is still saveable as Personal — what is
  refused is the Global feed, not the journal. Threats are blocked rather than blurred because
  blurring one still delivers it to anyone who taps.
- **Sensitive words (`sensitiveTerms` — slurs, or anything else listed) blur, they don't block.** The
  post reaches the Global feed and `MemoryRow` renders its text and media behind a tap-to-reveal, so
  each reader chooses. Three deliberate properties: detection runs **at render time**
  (`ContentModeration.isSensitive`), so the stored text is always exactly what the author wrote and a
  newly listed word also blurs posts that already exist; only the **Global feed** blurs
  (`blursSensitiveContent`), never Home, the calendar or a day view; and the **author never sees their
  own post blurred**. A reveal is per-row, per-session — revealing one post isn't a standing
  preference. VoiceOver is told "sensitive content, hidden" until revealed, otherwise the choice is
  one only sighted readers get to make. The server deliberately does **not** know about
  `sensitiveTerms`; if it hid those posts they'd never reach the feed to be blurred.
  Images are only blurred when the *text* matches — there's no image classifier.
- **Ordinary profanity is allowed.** People swear when they are upset; that is the app working.
- **Self-harm is never refused, but never broadcast.** Resources are offered **before** saving —
  showing them afterwards meant the moment had passed, and for a Global entry it had already
  reached strangers. "Save anyway" is the primary action and nothing is refused, flagged or
  reported; the only thing that changes is the destination, which is forced to **Personal**. The first
  version showed resources *and* still posted to Global — the worst of both, since the person gets
  a helpline while their crisis goes out to strangers. The Global feed is day-scoped and anonymous
  with no support structure, so it cannot help them and publishing it risks harm to whoever reads
  it. Framed as care, never as enforcement: `verdictFor` returns `selfHarm` rather than `policy`
  precisely so the notification copy differs. Never refuse to *save* it — gating someone's lowest
  moment would teach them this is a bad place to be honest, which is the opposite of the product.
- **Contact details** warn before a public post, never block.

**Flags are shown one at a time, and posting happens last.** `CreateMemoryView.attemptPost` builds a
queue of `PostFlag`s — threat, then self-harm, then sensitive, then contact details — and presents each
through a single `.sheet(item:onDismiss:)`. The author's choice is recorded, the sheet dismisses, and
only in `onDismiss` (after the dismissal has finished) does the next flag appear or the post and its
Global-feed redirect run. Choosing "Save as Personal" drops the Global-only flags still queued.
Swiping a flag away counts as "Edit": nothing posts without an explicit choice. Don't reintroduce
`pressPost()` inside a button action on a presented view — presenting and navigating in the same beat
is what made views flash up and vanish.

The first-post habit prompt lives on **`RootView`** (`RootView.habitPromptKey`), not the Create
screen: a Global post redirects to the feed, the custom tab bar tears Create down, and an alert
presented there appeared and disappeared immediately.

`MemoryModel.isSensitive` (also on the DTO, the Firestore doc and `decodeDTOManually`) is the author's
"Mark as sensitive" toggle, offered on Create only when the post is Global. Accepting the sensitive
flag sets it too. The feed blurs when **either** the flag is set **or** a listed word matches — the
flag is what covers an image, which the word list can't see.

**The word lists live in Firestore at `config/moderation`, and both layers read that one
document.** `ModerationList` fetches it once per launch and caches it in `UserDefaults`;
`moderation.ts` reads the same doc and caches it on the warm instance for 5 minutes. So a new term
takes effect within minutes, on both layers, by editing one document — no App Store release and no
functions deploy. Don't reintroduce a second copy in either place; the whole point is that they
can't drift.

Shape: `{ version: Int, sensitiveTerms: [String], blockedPhrases: [String], selfHarmPhrases: [String] }`.
`sensitiveTerms` (formerly `hateTerms`, which hid posts; renamed when the behaviour became blur) matches
whole-word after leetspeak normalisation (so `h4te` finds `hate`, and no variants need listing). `blockedPhrases` and `selfHarmPhrases` match their words **in order with up
to `maxPhraseGap` (2) other words between each pair** — plain substring matching let "I hope you all
die" past a list containing "hope you die". Implemented twice (`ContentModeration.phraseMatches`,
`moderation.ts phraseMatches`); same tokenizer, same gap, or the layers disagree. This raises the
ceiling on a word list without removing it: reordering, synonyms, misspellings and Tagalog still get
through, and only a semantic classifier closes that.
`version` is for cache invalidation and log legibility only — it is deliberately *not* a separate
version-check request, because that would cost an extra read to save a read.

`sensitiveTerms` lives in **`TodayI/Utils/SensitiveTerms.json`** — the one source for the list. The app
bundles it as its fallback (`ModerationTerms.bundledSensitiveTerms()`), and the same file is pushed to
`config/moderation`, where Firestore wins at runtime. To change it: edit the JSON, bump nothing in
code, then push the field and increment `version` (a REST PATCH with `gcloud auth print-access-token`
and `updateMask.fieldPaths=sensitiveTerms&updateMask.fieldPaths=version` works — clients can't write
`config`, the rules forbid it). The file's `_comment` records what was left out deliberately and why:
`shit`/`damn`/`ass` (everyday venting), `puke` (English "vomit"), `paki` (Taglish "please"), `gaga`
(Lady Gaga), `die`/`kill` (grief; threats are blocked separately). Whole-word matching means an
innocent English or Taglish word in the list blurs ordinary posts — check that before adding one.
Both sides fall back to built-in `blockedPhrases` so a fresh install is
never completely unfiltered before its first fetch, and both **fail open** on a fetch error: the
client keeps its cached list, the server keeps its warm one. Failing closed would hide every public
post in the app over one failed read.

**This needs a rule** — `config/{doc}` is signed-in read, no client write (console edits only).

`moderatePublicMemory` hides a violating post (`isPublic: false`, `moderationHidden: true`) rather
than deleting it, and writes the author an inbox notification; a post that silently vanishes reads
as a bug and teaches nothing. Private memories are never scanned.

## Deletion

**Account deletion happens in a Cloud Function, because it cannot be done correctly on the client.**
`deleteAccountData` (callable, `asia-southeast1`) uses the Admin SDK to reach three things rules put
permanently out of the client's reach: Storage files, the user's comments on *other people's* posts,
and their uid inside other users' `blockedUsers` arrays. `AuthStore.deleteAccount()` calls it and
only wipes local data once the server confirms.

Three bugs this replaced, worth not reintroducing:

- `listAll()` **is not recursive.** The old Storage cleanup iterated `listing.items` on
  `users/{uid}`, which is empty — every file sits under the `memories/` and `profile/` *prefixes*. So
  it deleted nothing, and since `downloadURL()` hands out tokened URLs that ignore Storage rules,
  every photo, video and voice note stayed publicly fetchable forever after the account was gone.
- **Firestore was deleted before Auth.** `requiresRecentLogin` is the *expected* error for a stale
  session, so the common failure destroyed the user's entire history while leaving the account alive
  with nothing left to retry. The Admin SDK has no recent-login requirement, so Auth deletion is
  reliable and runs last — anything that throws before it leaves the account intact and retryable.
- The local wipe cleared `["audio", "images"]`, but images are written to **`memories`** and videos
  to **`videos`**, so both survived on disk.

Reports are handled deliberately rather than uniformly: reports *about* the deleted user are removed,
reports they *filed* are kept with `reporterUID` scrubbed, since those are evidence about someone
else. Say so in the privacy policy — retaining anything after a deletion request should never be a
surprise.

**Going Global requires a real account, on every surface.** `CreateMemoryView.privacyBinding` has
gated this since the beginning, but `MemoryRow`'s badge wrote straight through to the model — so an
anonymous user could publish to the Global feed by saving privately first and flipping the badge
afterwards. Both now share the same shape: guest → `AuthView`, restricted → silently refuse. The
rule is about public posting, not about which screen you are on.

**Visibility is only changeable on the memory's own day** (`MemoryRow.canToggleVisibility`). The
feed shows one day and has no day picker, so publishing an older entry put it where nobody could
look — the toggle appeared to work and did nothing. Deleting an old memory is still allowed; that
is `canEditPrivacy`, deliberately a separate property.

A memory may have **no Firestore document** — a free user's Personal entry that was never uploaded,
or one whose remote copy was taken by `deleteMemory(scope: .remoteOnly)`. `updateData` fails with
`notFound` on both, so `updatePrivacy` catches that and calls `firstUpload`, which writes the whole
document via `CloudBackupService.backUpNow`. Don't "fix" this with `setData(merge:)` — that would
create a document with privacy fields and no text or mood. `backUpNow` ignores `isPremium` on
purpose: Premium buys *automatic* backup, not permission to post. If the upload fails the flag is
reverted, because showing "Global" when nothing reached the server is a lie the user can't see
through.

**Per-memory deletion is scoped.** `MemoryService.DeleteScope` offers `.remoteOnly` and `.everywhere`,
because "get this off the internet" and "destroy this" are different wishes and a journal shouldn't
force the second to get the first. `.remoteOnly` clears the remote pointers and `isPublic` so the row
doesn't chase dead URLs or re-publish itself. `users/{uid}/dates/{dayKey}` is deliberately left alone
either way — it carries moods for the calendar, never content.

`onMemoryDeleted` cleans up `comments/{memoryId}` when a memory goes. The client cannot: rules grant
no delete on the hub and only permit deleting your own replies, so a thread containing other people's
comments is unreachable from the app by design. Before this, deleting a post left the whole
conversation in Firestore permanently.

## Conventions

- Two-space indentation, `// MARK: -` section headers.
- `print` with emoji prefixes (`✅ ❌ 📤 ⏰`) is the established logging style in both Swift and TS.
  `LoggerManager.instance.logFirebaseCall()` marks Firestore entry points — keep calling it in new
  service methods.
- Date helpers live in `Extensions/DateExtension.swift` (`today`, `startOfDay(in:)`, `dayBounds(in:)`,
  `formattedDayKeyLocal(in:)`). Use them instead of building `Calendar` math inline.
- Mood colors come from `Mood.adaptiveColor`, which resolves light/dark through `UIColor`. Never
  hardcode a mood color.
- **Privacy reads "Personal" / "Global" in the UI, never "Private" / "Public".** "Global" pairs with
  the World Feed and "Personal" is warmer than "Private" for what is mostly a diary. `PrivacyBadge`
  owns the single `label` used by the full badge, compact mode's transient reveal and the
  accessibility value. The model field stays `isPublic` — this is wording, not data.
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
