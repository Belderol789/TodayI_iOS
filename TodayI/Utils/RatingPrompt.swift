//
//  RatingPrompt.swift
//  TodayI
//
//  When to ask for an App Store rating — and, as important, when not to.
//

import Foundation
import StoreKit
import UIKit

/// Asks for a rating through Apple's own sheet, at a good moment.
///
/// Apple shows that sheet at most three times a year per person and decides for itself
/// whether to show it at all, so this can't nag. What this adds is *timing*: the app is a
/// journal, and people open it on their worst days too. Asking someone who has just
/// written about a hard one would be careless and would get an honest one-star back, so
/// the prompt only follows a calm entry and never one that raised a support flag. That
/// is a product decision — don't move it to "after any save" to collect more reviews.
@MainActor
enum RatingPrompt {

  /// Entries saved before the first ask: enough that someone has formed an opinion.
  private static let firstAskAfter = 7
  /// Days between asks. Apple's cap is the hard limit; this is the courtesy one.
  private static let minimumDaysBetweenAsks = 120

  private static let countKey = "ratingPrompt.savedCount"
  private static let lastAskKey = "ratingPrompt.lastAskedAt"

  /// Where "Rate TodayI" in Settings goes: the App Store's review composer.
  static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6754281059?action=write-review")!

  /// Call after a memory is saved locally. Counts it, and asks if now is a good moment.
  static func entrySaved(mood: Mood, text: String) {
    let defaults = UserDefaults.standard
    let count = defaults.integer(forKey: countKey) + 1
    defaults.set(count, forKey: countKey)

    guard count >= firstAskAfter else { return }
    guard isCalm(mood: mood, text: text) else { return }
    if let last = defaults.object(forKey: lastAskKey) as? Date,
       Date().timeIntervalSince(last) < Double(minimumDaysBetweenAsks) * 86_400 {
      return
    }

    defaults.set(Date(), forKey: lastAskKey)
    // Later, so it doesn't collide with the preview sheet or the redirect to the feed
    // that follow a save — presenting over a screen mid-transition is how views flash up
    // and vanish.
    Task {
      try? await Task.sleep(for: .seconds(2.5))
      guard let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }) else { return }
      AppStore.requestReview(in: scene)
    }
  }

  /// A calm entry: a lighter mood, and nothing the content filter would show support for.
  static func isCalm(mood: Mood, text: String) -> Bool {
    guard [.happy, .neutral, .surprise].contains(mood) else { return false }
    let findings = ContentModeration.scan(text)
    return findings.isDisjoint(with: [.selfHarm, .violentThreat, .hate])
  }
}
