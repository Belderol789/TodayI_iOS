//
//  StreakPill.swift
//  TodayI
//

import SwiftUI

/// Duolingo-style day counter. Deliberately **not** gated behind Premium — it exists
/// to bring people back, and a paywalled streak would do the opposite.
///
/// Always visible, including at zero: hiding it meant a new user never learned the
/// mechanic existed, so there was nothing to start.
struct StreakPill: View {
  let streak: StreakInfo
  /// Tapping goes to Create while today is unwritten — the pill is the nudge, so it
  /// should also be the shortcut. No-op once today is logged.
  var onTap: (() -> Void)? = nil

  private var hasStreak: Bool { streak.days > 0 }

  /// Lit once today is written; hollow and muted while the streak is at risk or
  /// not yet started, which is the whole nudge.
  private var tint: Color {
    streak.loggedToday ? Color.orange : Color.secondary
  }

  var body: some View {
    Button {
      onTap?()
    } label: {
      HStack(spacing: 5) {
        Image(systemName: streak.loggedToday ? "flame.fill" : "flame")
          .font(.subheadline.weight(.semibold))

        if hasStreak {
          Text("\(streak.days)")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .contentTransition(.numericText())
        } else {
          // "Start" rather than a bare 0 — a zero reads as failure, and the header
          // has no room for a longer phrase beside the title and Profile button.
          Text("Start")
            .font(.subheadline.weight(.semibold))
        }
      }
      .foregroundStyle(tint)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        Capsule().fill(tint.opacity(streak.loggedToday ? 0.15 : 0.10))
      )
    }
    .buttonStyle(.plain)
    .disabled(onTap == nil)
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: streak)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityHint(onTap == nil ? "" : "Opens a new memory.")
  }

  private var accessibilityText: String {
    guard hasStreak else { return "No streak yet. Post today to start one." }
    let base = streak.days == 1 ? "1 day streak" : "\(streak.days) day streak"
    return streak.loggedToday
    ? "\(base). Today is logged."
    : "\(base). Today is not logged yet."
  }
}

#Preview("Streak states") {
  VStack(spacing: 16) {
    StreakPill(streak: StreakInfo(days: 7, loggedToday: true))
    StreakPill(streak: StreakInfo(days: 7, loggedToday: false))
    StreakPill(streak: StreakInfo(days: 1, loggedToday: true))
    StreakPill(streak: .none)
  }
  .padding()
}
