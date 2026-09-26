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
    /// Slurs and dehumanising language. Blocked from the Global feed.
    case hateSpeech
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
  static let blocking: Set<Finding> = [.hateSpeech, .violentThreat]

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
    if list.selfHarmPhrases.contains(where: haystack.contains) { findings.insert(.selfHarm) }
    if list.blockedPhrases.contains(where: haystack.contains) { findings.insert(.violentThreat) }
    if list.hateTerms.contains(where: { containsWord($0, in: haystack) }) {
      findings.insert(.hateSpeech)
    }
    if containsContactDetails(text) { findings.insert(.personalInfo) }

    return findings
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
