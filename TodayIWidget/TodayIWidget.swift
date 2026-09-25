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

  private var snapshot: StreakSnapshot { entry.snapshot }
  private var tint: Color { snapshot.loggedToday ? .orange : .secondary }

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
    default:
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
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
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
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
  }
}

#Preview(as: .systemSmall) {
  TodayIWidget()
} timeline: {
  StreakEntry(date: .now, snapshot: StreakSnapshot(days: 12, loggedToday: true, updatedAt: .now))
  StreakEntry(date: .now, snapshot: StreakSnapshot(days: 12, loggedToday: false, updatedAt: .now))
  StreakEntry(date: .now, snapshot: StreakSnapshot(days: 0, loggedToday: false, updatedAt: nil))
}
