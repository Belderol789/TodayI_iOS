//
//  TodayIWidget.swift
//  TodayIWidget
//

import WidgetKit
import SwiftUI

struct StreakEntry: TimelineEntry {
  let date: Date
  let snapshot: StreakSnapshot
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> StreakEntry {
    StreakEntry(date: Date(), snapshot: .placeholder)
  }

  func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
    // The gallery preview shouldn't show someone a 0 they haven't earned.
    let snapshot = context.isPreview ? StreakSnapshot.placeholder : StreakSnapshot.read()
    completion(StreakEntry(date: Date(), snapshot: snapshot))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
    let entry = StreakEntry(date: Date(), snapshot: StreakSnapshot.read())
    // The app reloads this explicitly whenever the streak changes, so the only thing
    // a scheduled refresh buys is catching midnight — when an untouched streak goes
    // from "logged today" to "at risk". Next local midnight is enough.
    let midnight = Calendar.current.nextDate(
      after: Date(),
      matching: DateComponents(hour: 0, minute: 1),
      matchingPolicy: .nextTime
    ) ?? Date().addingTimeInterval(60 * 60)
    completion(Timeline(entries: [entry], policy: .after(midnight)))
  }
}

struct TodayIWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  var entry: Provider.Entry

  @Environment(\.colorScheme) private var scheme
  private var snapshot: StreakSnapshot { entry.snapshot }
  private var tint: Color { snapshot.loggedToday ? .orange : .secondary }

  /// Only shown while it's actually today's mood — the app refreshes this when the
  /// World feed loads, so it can otherwise be a day behind.
  private var world: WorldMood? {
    guard let world = snapshot.world, world.isFresh, world.total > 0 else { return nil }
    return world
  }

  /// The app publishes both appearances, so the widget never needs the mood palette.
  private func worldColor(_ world: WorldMood) -> Color {
    Color(hex: scheme == .dark ? world.darkHex : world.lightHex)
  }

  /// Mirrors `StreakPill`: lit once today is written, hollow while it's still at risk.
  private var flame: String { snapshot.loggedToday ? "flame.fill" : "flame" }

  private var caption: String {
    if snapshot.days == 0 { return "Start a streak" }
    if snapshot.loggedToday { return snapshot.days == 1 ? "day" : "days" }
    return "Today's still open"
  }

  var body: some View {
    switch family {
    case .accessoryCircular:
      // No colour to rely on at this size, so the icon carries the state.
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: 0) {
          Image(systemName: flame).font(.caption)
          Text("\(snapshot.days)").font(.headline.weight(.bold))
        }
      }
    case .accessoryInline:
      Label("\(snapshot.days) day streak", systemImage: flame)
    case .systemMedium:
      HStack(spacing: 16) {
        streakBlock
        if let world {
          Divider()
          worldBlock(world)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    default:
      VStack(alignment: .leading, spacing: 6) {
        streakBlock
        if let world {
          Spacer(minLength: 0)
          worldRow(world)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
  }

  private var streakBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: flame)
        .font(.title3.weight(.semibold))
        .foregroundStyle(tint)
      Text("\(snapshot.days)")
        .font(.system(size: 38, weight: .bold, design: .rounded))
        .monospacedDigit()
        .contentTransition(.numericText())
      Text(caption)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
  }

  /// Compact enough to sit under the streak on a small widget.
  private func worldRow(_ world: WorldMood) -> some View {
    HStack(spacing: 5) {
      Circle()
        .fill(worldColor(world))
        .frame(width: 8, height: 8)
      Text(world.name)
        .font(.caption.weight(.semibold))
        .foregroundStyle(worldColor(world))
      Text("\(world.percent)%")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .lineLimit(1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("The world feels \(world.name), \(world.percent) percent")
  }

  private func worldBlock(_ world: WorldMood) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("The world feels")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(world.name)
        .font(.system(size: 26, weight: .bold, design: .rounded))
        .foregroundStyle(worldColor(world))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text("\(world.percent)% of \(world.total) today")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("The world feels \(world.name), \(world.percent) percent of \(world.total) memories today")
  }
}

struct TodayIWidget: Widget {
  /// Must match `StreakSnapshot.widgetKind` in the app, or reload requests miss.
  let kind: String = "TodayIStreakWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      TodayIWidgetEntryView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Streak")
    .description("How many days in a row you've journaled.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
  }
}

#Preview(as: .systemSmall) {
  TodayIWidget()
} timeline: {
  StreakEntry(date: .now, snapshot: .placeholder)
  StreakEntry(date: .now, snapshot: StreakSnapshot(days: 12, loggedToday: false,
                                                   updatedAt: .now, world: nil))
  StreakEntry(date: .now, snapshot: StreakSnapshot(days: 0, loggedToday: false,
                                                   updatedAt: nil, world: nil))
}


extension Color {
  /// "RRGGBB" as published by the app. Falls back to a neutral rather than throwing
  /// away the whole timeline entry over a malformed string.
  init(hex: String) {
    var value: UInt64 = 0
    guard Scanner(string: hex).scanHexInt64(&value), hex.count == 6 else {
      self = .secondary
      return
    }
    self = Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }
}
