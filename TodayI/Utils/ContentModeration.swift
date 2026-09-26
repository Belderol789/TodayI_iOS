//
//  ContentModeration.swift
//  TodayI
//
//  Client half of a two-layer filter. This one is fast and bypassable — it exists to
//  give feedback while someone is still typing. `moderation.ts` re-runs the same
//  categories server-side on public posts, reading the same Firestore document, which
//  is the half that actually enforces.
//

import Foundation

/// What a scan found. Deliberately tiered, because the right response differs sharply.
enum ContentModeration {

  enum Finding: String, CaseIterable {
    /// A word from `sensitiveTerms` — slurs, or anything else listed. **Not blocked:**
    /// the post goes to the Global feed blurred, and each reader decides whether to
    /// reveal it. See `isSensitive(_:)`.
    case sensitive
    /// Threats of violence toward others. Blocked from the Global feed.
    case violentThreat
    /// Signals of self-harm or suicidal intent. **Never blocked.**
    case selfHarm
    /// Phone numbers, emails, street addresses. Warned about, not blocked.
    case personalInfo
  }

  /// Categories that prevent a post reaching the Global feed.
  ///
  /// `selfHarm` is deliberately absent. This is a mood journal whose entire premise is
  /// that people can be honest about feeling terrible; a filter that silences someone at
  /// their lowest — or worse, makes them feel reported for it — would do more harm than
  /// any slur it caught. Those posts are surfaced to the *author* with crisis resources
  /// and otherwise left completely alone.
  ///
  /// Ordinary profanity is absent for the same reason: people swear when they are upset,
  /// and that is the app working, not failing.
  ///
  /// `sensitive` is absent too: those posts are blurred with a tap to reveal rather than
  /// refused, so the reader chooses. Threats stay blocked because blurring one still
  /// delivers it to anyone who taps.
  static let blocking: Set<Finding> = [.violentThreat]

  // MARK: - Term lists
  //
  // Sourced from `ModerationList`, which caches `config/moderation` from Firestore. That
  // means the lists change by editing one document — no App Store release — and the
  // server-side enforcer reads the *same* document, so the two layers can't drift.

  private static var terms: ModerationTerms { ModerationList.current }

  // MARK: - Detectors

  private static let phoneRegex = try? NSRegularExpression(
    pattern: #"(?<!\d)(\+?\d[\d\s().-]{7,}\d)(?!\d)"#
  )
  private static let emailRegex = try? NSRegularExpression(
    pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
    options: .caseInsensitive
  )

  // MARK: - Scan

  /// Returns every category present in `text`.
  static func scan(_ text: String) -> Set<Finding> {
    let haystack = normalise(text)
    var findings: Set<Finding> = []

    let list = terms
    let words = tokens(haystack)
    if list.selfHarmPhrases.contains(where: { phraseMatches($0, in: words) }) {
      findings.insert(.selfHarm)
    }
    if list.blockedPhrases.contains(where: { phraseMatches($0, in: words) }) {
      findings.insert(.violentThreat)
    }
    if list.sensitiveTerms.contains(where: { containsWord($0, in: haystack) }) {
      findings.insert(.sensitive)
    }
    if containsContactDetails(text) { findings.insert(.personalInfo) }

    return findings
  }

  /// True when a Global post should render blurred behind a tap-to-reveal.
  ///
  /// Evaluated when the feed draws, not when the post is saved. That's deliberate: the
  /// stored text is always exactly what the author wrote, and a word added to
  /// `config/moderation` blurs posts that already exist rather than only new ones.
  static func isSensitive(_ text: String) -> Bool {
    let list = terms
    guard !list.sensitiveTerms.isEmpty else { return false }
    let haystack = normalise(text)
    return list.sensitiveTerms.contains(where: { containsWord($0, in: haystack) })
  }

  /// True when the text may not be posted to the Global feed.
  static func blocksPublicPost(_ text: String) -> Bool {
    !scan(text).isDisjoint(with: blocking)
  }

  // MARK: - Helpers

  /// Lowercases, collapses whitespace, and flattens the usual evasions (`h a t e`,
  /// `h.a.t.e`, `h4te`) so the list doesn't have to enumerate them.
  private static func normalise(_ text: String) -> String {
    let lowered = text.lowercased()
      .folding(options: .diacriticInsensitive, locale: .current)
      .replacingOccurrences(of: "0", with: "o")
      .replacingOccurrences(of: "1", with: "i")
      .replacingOccurrences(of: "3", with: "e")
      .replacingOccurrences(of: "4", with: "a")
      .replacingOccurrences(of: "5", with: "s")
      .replacingOccurrences(of: "@", with: "a")
      .replacingOccurrences(of: "$", with: "s")
    return lowered.replacingOccurrences(
      of: #"\s+"#, with: " ", options: .regularExpression
    )
  }

  // MARK: - Phrase matching
  //
  // Literal substring matching was trivially beaten by a single inserted word: the list
  // had "hope you die", someone typed "I hope you ALL die", and it sailed through — not
  // even adversarially. Phrases now match their words *in order* with up to
  // `maxPhraseGap` unrelated words between each pair, which catches "hope you all die",
  // "kill all of you" and similar near-misses without matching words scattered across an
  // entire journal entry.
  //
  // This raises the ceiling on a word list; it doesn't remove it. Reordering, synonyms,
  // misspellings and other languages still get through. **Keep in step with
  // `phraseMatches` in functions/src/moderation.ts** — same tokenizer, same gap.

  static let maxPhraseGap = 2

  /// Splits normalised text into bare words, dropping punctuation so "die." and "die!"
  /// both match "die".
  private static func tokens(_ haystack: String) -> [String] {
    haystack
      .split(separator: " ")
      .map { $0.filter { $0.isLetter || $0.isNumber } }
      .filter { !$0.isEmpty }
  }

  /// True when every word of `phrase` appears in `words`, in order, with at most
  /// `maxPhraseGap` other words between consecutive phrase words.
  static func phraseMatches(_ phrase: String, in words: [String]) -> Bool {
    let target = tokens(phrase)
    guard let first = target.first, words.count >= target.count else { return false }

    for start in words.indices where words[start] == first {
      var cursor = start
      var matched = true
      for word in target.dropFirst() {
        let window = (cursor + 1)..<min(cursor + 2 + maxPhraseGap, words.count)
        guard let hit = window.first(where: { words[$0] == word }) else {
          matched = false
          break
        }
        cursor = hit
      }
      if matched { return true }
    }
    return false
  }

  /// Whole-word match, so "class" can't trip on a term inside it — the Scunthorpe
  /// problem, which is exactly how naive filters end up censoring innocent words.
  private static func containsWord(_ term: String, in haystack: String) -> Bool {
    guard let regex = try? NSRegularExpression(
      pattern: "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
    ) else { return false }
    let range = NSRange(haystack.startIndex..., in: haystack)
    return regex.firstMatch(in: haystack, range: range) != nil
  }

  private static func containsContactDetails(_ text: String) -> Bool {
    let range = NSRange(text.startIndex..., in: text)
    if emailRegex?.firstMatch(in: text, range: range) != nil { return true }
    // Require 9+ digits so dates, times and "2026" don't look like phone numbers.
    if let match = phoneRegex?.firstMatch(in: text, range: range),
       let r = Range(match.range, in: text) {
      return text[r].filter(\.isNumber).count >= 9
    }
    return false
  }
}

// MARK: - Crisis resources

extension ContentModeration {
  /// Shown to the author when `.selfHarm` is found. Never shown to anyone else, never
  /// logged, never reported — the whole point is that it costs the user nothing to have
  /// been honest.
  struct CrisisResource: Identifiable {
    let id = UUID()
    let region: String
    let name: String
    let contact: String
  }

  static let crisisResources: [CrisisResource] = [
    .init(region: "Philippines", name: "NCMH Crisis Hotline", contact: "1553"),
    .init(region: "United States", name: "Suicide & Crisis Lifeline", contact: "988"),
    .init(region: "United Kingdom", name: "Samaritans", contact: "116 123"),
    .init(region: "Worldwide", name: "Find a helpline", contact: "findahelpline.com")
  ]
}
