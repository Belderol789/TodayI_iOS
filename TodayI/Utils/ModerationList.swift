//
//  ModerationList.swift
//  TodayI
//
//  The word list, fetched from Firestore and cached on device.
//

import Foundation
import FirebaseFirestore

/// Terms and phrases the filter matches against.
///
/// Lives in Firestore at `config/moderation` so it can be changed by editing one
/// document — no App Store release, no functions deploy. The **same document** is read by
/// `moderation.ts`, which is what keeps the typing-time warning and the server-side
/// enforcement from drifting apart. Edit it once, both layers follow.
struct ModerationTerms: Codable, Equatable {
  /// Bumped by hand when the lists change. Only used to skip re-parsing and to make a
  /// stale cache obvious in logs — the whole document is fetched either way, because a
  /// separate version read would cost the same as just reading the document.
  var version: Int
  /// Words that get a post **blurred** in the Global feed, with a tap to reveal.
  /// Matched whole-word after leetspeak normalisation, at render time — so adding a
  /// term also blurs posts that already exist. Slurs belong here; so does anything else
  /// a reader should get to opt into rather than have pushed at them.
  var sensitiveTerms: [String]
  /// Matched as substrings, so multi-word threats work.
  var blockedPhrases: [String]
  /// Drives the support sheet. Never blocks anything.
  var selfHarmPhrases: [String]

  /// Used before the first successful fetch, and if the document is missing.
  ///
  /// `sensitiveTerms` is empty on purpose — which words to blur is a live content
  /// decision made in `config/moderation`. The phrases are here because they're generic
  /// enough to be safe defaults, and because shipping with *nothing* would mean a
  /// brand-new install has no filter at all until its first network round trip.
  static let fallback = ModerationTerms(
    version: 0,
    sensitiveTerms: [],
    blockedPhrases: [
      "kill you", "kill him", "kill her", "kill them",
      "hunt you down", "beat you up", "i will find you",
      "you should die", "hope you die"
    ],
    selfHarmPhrases: [
      "kill myself", "killing myself", "end my life", "ending my life",
      "want to die", "wanna die", "better off dead", "no reason to live",
      "nothing to live for", "take my own life", "suicidal", "suicide",
      "hurt myself", "hurting myself", "self harm", "self-harm",
      "cut myself", "cutting myself", "don't want to be here anymore",
      "dont want to be here anymore", "can't go on", "cant go on"
    ]
  )
}

enum ModerationList {

  // v2: `hateTerms` became `sensitiveTerms`. A new key rather than a migration — the
  // cache is disposable and refetched every launch anyway.
  private static let cacheKey = "moderation.terms.v2"

  /// The list the filter actually uses. Read synchronously from `ContentModeration.scan`,
  /// so it's a plain cached value rather than something awaited per keystroke.
  private(set) static var current: ModerationTerms = loadCache() ?? .fallback

  /// Fetches the list and updates the cache. One document read.
  ///
  /// **Fails silently and keeps the cached list.** A network blip must not leave the app
  /// unfiltered *or* unable to post — and it can't do real damage either way, because
  /// `moderatePublicMemory` re-checks every public post server-side. The client copy is
  /// for instant feedback; the server copy is the control.
  static func refresh() async {
    do {
      LoggerManager.instance.logFirebaseCall()
      let snap = try await Firestore.firestore()
        .collection("config").document("moderation").getDocument()

      guard let data = snap.data() else {
        print("ℹ️ config/moderation missing — keeping list v\(current.version)")
        return
      }

      let fetched = ModerationTerms(
        version: data["version"] as? Int ?? 0,
        sensitiveTerms: lowercased(data["sensitiveTerms"]),
        blockedPhrases: lowercased(data["blockedPhrases"]),
        selfHarmPhrases: lowercased(data["selfHarmPhrases"])
      )

      guard fetched != current else { return }
      current = fetched
      saveCache(fetched)
      print("✅ Moderation list updated to v\(fetched.version) "
            + "(\(fetched.sensitiveTerms.count) sensitive terms, \(fetched.blockedPhrases.count) blocked phrases)")
    } catch {
      print("⚠️ Moderation list fetch failed, using cached v\(current.version):", error)
    }
  }

  // MARK: - Helpers

  private static func lowercased(_ value: Any?) -> [String] {
    ((value as? [String]) ?? [])
      .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
      .filter { !$0.isEmpty }
  }

  private static func loadCache() -> ModerationTerms? {
    guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
    return try? JSONDecoder().decode(ModerationTerms.self, from: data)
  }

  private static func saveCache(_ terms: ModerationTerms) {
    guard let data = try? JSONEncoder().encode(terms) else { return }
    UserDefaults.standard.set(data, forKey: cacheKey)
  }
}
