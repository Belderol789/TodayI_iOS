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

  /// 0 at the start, 1 by three weeks. Drives how hot the flame looks, so the pill
  /// visibly earns its colour rather than flipping between two states.
  private var intensity: Double {
    min(1.0, Double(streak.days) / 21.0)
  }

  /// A streak long enough that losing it would sting — worth a little life.
  private var isMilestone: Bool { streak.days >= 10 }

  /// Lit once today is written; hollow and muted while the streak is at risk or
  /// not yet started, which is the whole nudge.
  private var tint: Color {
    streak.loggedToday ? Color.orange : Color.secondary
  }

  /// Saturation and brightness climb with the streak. Applied as modifiers on
  /// `.orange` rather than a hardcoded RGB so it still resolves per colour scheme.
  private var flameSaturation: Double { streak.loggedToday ? 0.75 + 0.45 * intensity : 1 }
  private var flameBrightness: Double { streak.loggedToday ? 0.10 * intensity : 0 }

  /// The glow breathes at 10+; below that it's a static, subtle halo.
  private var glowRadius: CGFloat {
    guard streak.loggedToday else { return 0 }
    let base = 1 + 3 * intensity
    return isMilestone && pulse ? base * 2.2 : base
  }

  /// Drives the milestone glow. Never animates layout — a repeating `scaleEffect`
  /// here would visually spill into the Profile button beside it.
  @State private var pulse = false

  var body: some View {
    Button {
      onTap?()
    } label: {
      HStack(spacing: 5) {
        Image(systemName: streak.loggedToday ? "flame.fill" : "flame")
          .font(.subheadline.weight(.semibold))
          .saturation(flameSaturation)
          .brightness(flameBrightness)
          .shadow(color: tint.opacity(streak.loggedToday ? 0.55 : 0), radius: glowRadius)

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
    }
    .buttonStyle(.plain)
    .disabled(onTap == nil)
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: streak)
    .onAppear { syncPulse() }
    .onChange(of: isMilestone) { _, _ in syncPulse() }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityHint(onTap == nil ? "" : "Opens a new memory.")
  }

  /// Starts or stops the breathing glow. Guarded so the repeating animation never
  /// runs for a streak that hasn't earned it.
  private func syncPulse() {
    guard isMilestone, streak.loggedToday else {
      pulse = false
      return
    }
    withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
      pulse = true
    }
  }

  private var accessibilityText: String {
    guard streak.days > 0 else { return "No streak yet. Post today to start one." }
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
