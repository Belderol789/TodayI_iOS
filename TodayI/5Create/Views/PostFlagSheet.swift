//
//  PostFlagSheet.swift
//  TodayI
//
//  The views shown between tapping Post and the post going out.
//

import SwiftUI

/// Something the content filter wants the author to see before posting.
///
/// These are shown **one at a time, in this order**, by `CreateMemoryView`. Each one is
/// answered and fully dismissed before the next appears, and the post itself — plus the
/// redirect to the Global feed — happens only after the last one has gone. Presenting
/// and navigating in the same beat is what made views flash up and vanish before.
enum PostFlag: String, Identifiable {
  /// A threat. Can't go on the Global feed at all.
  case threat
  /// Self-harm. Support first; the entry is always kept Personal.
  case selfHarm
  /// A listed sensitive word. Can go out, blurred behind a tap-to-reveal.
  case sensitive
  /// A phone number or email address. Can go out, after a warning.
  case contactDetails

  var id: String { rawValue }

  /// Only meaningful for a Global post, so dropped the moment the post becomes Personal.
  /// Self-harm is the exception: the support card matters wherever the entry is going.
  var requiresGlobal: Bool { self != .selfHarm }
}

/// What the author chose on a flag.
enum PostFlagChoice {
  /// Carry on as-is.
  case proceed
  /// Carry on, but mark the post sensitive so the feed blurs it.
  case markSensitive
  /// Carry on, but keep this entry off the Global feed.
  case keepPersonal
  /// Stop and go back to editing. Swiping the sheet away means this too.
  case edit
}

struct PostFlagSheet: View {
  let flag: PostFlag
  /// Whether the post was headed for the Global feed when this flag appeared — changes
  /// what the self-harm card promises.
  let wasGlobal: Bool
  let onChoose: (PostFlagChoice) -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          header
          if flag == .selfHarm { resources }
        }
        .padding(20)
      }
      .safeAreaInset(edge: .bottom) { actions }
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents(flag == .selfHarm ? [.medium, .large] : [.medium])
  }

  // MARK: - Copy

  private var navigationTitle: String {
    switch flag {
    case .threat:         return "Global feed"
    case .selfHarm:       return "You're not alone"
    case .sensitive:      return "Sensitive content"
    case .contactDetails: return "Contact details"
    }
  }

  private var icon: String {
    switch flag {
    case .threat:         return "hand.raised.fill"
    case .selfHarm:       return "heart.fill"
    case .sensitive:      return "eye.slash.fill"
    case .contactDetails: return "person.text.rectangle"
    }
  }

  private var title: String {
    switch flag {
    case .threat:         return "This can't go on the Global feed"
    case .selfHarm:       return "That sounded like a hard day."
    case .sensitive:      return "Sensitive content detected"
    case .contactDetails: return "Sharing contact details?"
    }
  }

  private var message: String {
    switch flag {
    case .threat:
      return "Posts on the Global feed can't contain threats. You can still save this entry just for yourself."
    case .selfHarm:
      // Care, never enforcement: nothing here suggests a rule was broken.
      return wasGlobal
        ? "Whenever you're ready, your entry will be saved exactly as you wrote it — kept Personal rather than posted to the Global feed. Nothing is flagged or reported. If you'd rather talk to someone, these are free and confidential."
        : "Whenever you're ready, your entry will be saved exactly as you wrote it. Nothing is flagged or reported. If you'd rather talk to someone, these are free and confidential."
    case .sensitive:
      return "This post will appear blurred on the Global feed. Readers will see your name and mood, and choose whether to tap and view it."
    case .contactDetails:
      return "This looks like it contains a phone number or email address. Anyone can read posts on the Global feed."
    }
  }

  // MARK: - Sections

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      Text(title)
        .font(.title2.weight(.semibold))
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var resources: some View {
    ForEach(ContentModeration.crisisResources) { resource in
      VStack(alignment: .leading, spacing: 2) {
        Text(resource.name).font(.subheadline.weight(.semibold))
        Text(resource.contact).font(.title3.weight(.bold)).foregroundStyle(.tint)
        Text(resource.region).font(.caption).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
  }

  @ViewBuilder
  private var actions: some View {
    VStack(spacing: 10) {
      switch flag {
      case .threat:
        primary("Save as Personal", .keepPersonal)
        secondary("Edit", .edit)
      case .selfHarm:
        // Primary on purpose. Nothing here is a gate — it only ever keeps it Personal.
        primary("Save anyway", .keepPersonal)
        secondary("Keep writing", .edit)
      case .sensitive:
        primary("Post anyway", .markSensitive)
        secondary("Save as Personal", .keepPersonal)
        secondary("Edit", .edit)
      case .contactDetails:
        primary("Post anyway", .proceed)
        secondary("Save as Personal", .keepPersonal)
        secondary("Edit", .edit)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 10)
    .padding(.bottom, 16)
    .background(.bar)
  }

  private func primary(_ label: String, _ choice: PostFlagChoice) -> some View {
    Button { onChoose(choice) } label: {
      Text(label)
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Capsule().fill(Color.accentColor))
        .foregroundStyle(.white)
    }
    .buttonStyle(.plain)
  }

  private func secondary(_ label: String, _ choice: PostFlagChoice) -> some View {
    Button(label) { onChoose(choice) }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 4)
  }
}
