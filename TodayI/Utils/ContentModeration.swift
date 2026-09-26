//
//  ContentModeration.swift
//  TodayI
//
//  Client half of a two-layer filter. This one is fast and bypassable — it exists to
//  give feedback while someone is still typing. `moderation.ts` re-runs the same
//  categories server-side on public posts, which is the half that actually enforces.
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

  /// Clinical and colloquial phrasings that suggest self-harm or suicidal intent.
  ///
  /// Tuned to over-match rather than under-match: a false positive costs someone a
  /// dismissable card of support, a false negative costs the only moment we had to show
  /// it. Phrases, not single words, so "I could kill for a coffee" doesn't trip it.
  private static let selfHarmPhrases = [
    "kill myself", "killing myself", "end my life", "ending my life",
    "want to die", "wanna die", "better off dead", "no reason to live",
    "nothing to live for", "take my own life", "suicidal", "suicide",
    "hurt myself", "hurting myself", "self harm", "self-harm",
    "cut myself", "cutting myself", "don't want to be here anymore",
    "dont want to be here anymore", "can't go on", "cant go on"
  ]

  /// Loaded from `HateTerms.txt` in the bundle rather than hardcoded.
  ///
  /// A slur list is a maintenance burden with real consequences in both directions, and
  /// it should come from a maintained source (Shutterstock's `List-of-Dirty-Naughty-...`
  /// or a vendor feed) and be updatable without an App Store release. Shipping an empty
  /// file is honest: the plumbing is live and the list is a content decision.
  /// **`moderation.ts` holds the authoritative copy — this one is only for fast feedback.**
  private static let hateTerms: [String] = loadList(named: "HateTerms")

  private static let violentPhrases = [
    "kill you", "kill him", "kill her", "kill them",
    "hunt you down", "beat you up", "i will find you",
    "you should die", "hope you die"
  ]

  private static func loadList(named name: String) -> [String] {
    guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
          let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return raw
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
      .filter { !$0.isEmpty && !$0.hasPrefix("#") }
  }

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

    if selfHarmPhrases.contains(where: haystack.contains) { findings.insert(.selfHarm) }
    if violentPhrases.contains(where: haystack.contains) { findings.insert(.violentThreat) }
    if !hateTerms.isEmpty, hateTerms.contains(where: { containsWord($0, in: haystack) }) {
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
