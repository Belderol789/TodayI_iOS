//
//  StreakPill.swift
//  TodayI
//

import SwiftUI

/// Duolingo-style day counter. Deliberately **not** gated behind Premium — it exists
/// to bring people back, and a paywalled streak would do the opposite.
struct StreakPill: View {
  let streak: StreakInfo

  /// Lit once today is written; hollow and muted while the streak is still at risk,
  /// which is the whole nudge.
  private var tint: Color {
    streak.loggedToday ? Color.orange : Color.secondary
  }

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: streak.loggedToday ? "flame.fill" : "flame")
        .font(.subheadline.weight(.semibold))
      Text("\(streak.days)")
        .font(.subheadline.weight(.bold))
        .monospacedDigit()
        .contentTransition(.numericText())
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      Capsule().fill(tint.opacity(streak.loggedToday ? 0.15 : 0.10))
    )
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: streak)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(streak.days == 1 ? "1 day streak" : "\(streak.days) day streak")
    .accessibilityValue(streak.loggedToday
                        ? "Today is logged."
                        : "Today is not logged yet.")
  }
}

#Preview("Streak states") {
  VStack(spacing: 16) {
    StreakPill(streak: StreakInfo(days: 7, loggedToday: true))
    StreakPill(streak: StreakInfo(days: 7, loggedToday: false))
    StreakPill(streak: StreakInfo(days: 1, loggedToday: true))
  }
  .padding()
}
