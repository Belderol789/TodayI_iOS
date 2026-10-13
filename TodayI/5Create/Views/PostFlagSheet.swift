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
  /// Shown from an existing entry's Global badge rather than from Create. There is nothing
  /// to save or edit there — the entry already exists and simply stays Personal — so the
  /// copy explains that and the only action is OK.
  var sharingExisting = false
  /// What the author wrote, for "Send this to someone you trust".
  var entryText = ""
  let onChoose: (PostFlagChoice) -> Void

  @State private var checkInDate: Date?
  @State private var checkInUnavailable = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          header
          if flag == .selfHarm {
            careOptions
            resources
          }
        }
        .padding(20)
      }
      .safeAreaInset(edge: .bottom) { actions }
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
    }
    // Full height for self-harm, so the people to reach and the helplines are all on
    // screen without a scroll.
    .presentationDetents(flag == .selfHarm ? [.large] : [.medium])
    .task {
      if flag == .selfHarm {
        checkInDate = await NotificationManager.shared.pendingCareCheckInDate()
      }
    }
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
    if sharingExisting {
      switch flag {
      case .selfHarm:
        return "This entry stays Personal. Entries like this aren't shared to the Global feed — nothing is flagged or reported, and it's still saved exactly as you wrote it."
      case .threat:
        return "Posts on the Global feed can't contain threats, so this entry stays Personal. It's still saved just for you."
      default:
        break
      }
    }
    switch flag {
    case .threat:
      return "Posts on the Global feed can't contain threats. You can still save this entry just for yourself."
    case .selfHarm:
      // Care, never enforcement: nothing here suggests a rule was broken.
      return wasGlobal
        ? "Whenever you're ready, your entry will be saved exactly as you wrote it — kept Personal rather than posted to the Global feed. Nothing is flagged or reported."
        : "Whenever you're ready, your entry will be saved exactly as you wrote it. Nothing is flagged or reported."
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

  // Keeping an entry like this off the feed protects strangers, but it can leave the
  // writer feeling unheard. These point them at people who can actually respond: someone
  // who knows them, and the app itself tomorrow. Neither sends anything to a server.
  private var careOptions: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionLabel("Reach out")

      if !entryText.isEmpty {
        ShareLink(item: entryText) {
          careRow(icon: "paperplane.fill",
                  title: "Send this to someone you trust",
                  detail: "Share what you wrote with a friend or family member. Only the person you choose will see it.")
        }
        .buttonStyle(.plain)
      }

      Button {
        // Not `.disabled` once it's set: that greys out the confirmation, which then
        // reads as something that failed.
        guard checkInDate == nil else { return }
        Task {
          if let date = await NotificationManager.shared.scheduleCareCheckIn() {
            checkInDate = date
          } else {
            checkInUnavailable = true
          }
        }
      } label: {
        careRow(icon: checkInDate == nil ? "bell.fill" : "checkmark.circle.fill",
                title: checkInDate == nil ? "Check in with me tomorrow" : "We'll check in \(checkInPhrase)",
                detail: checkInUnavailable
                  ? "Notifications are off for TodayI. You can turn them on in the Settings app."
                  : "One gentle notification, no more. It won't mention what you wrote.")
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(checkInDate == nil ? [] : .isStaticText)
    }
  }

  private var checkInPhrase: String {
    guard let checkInDate else { return "" }
    let time = checkInDate.formatted(date: .omitted, time: .shortened)
    return Calendar.current.isDateInToday(checkInDate) ? "at \(time)" : "tomorrow at \(time)"
  }

  private func careRow(icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .font(.body)
        .foregroundStyle(.tint)
        .frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    .contentShape(RoundedRectangle(cornerRadius: 12))
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.top, 4)
  }

  private var resources: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionLabel("Free, confidential helplines")
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
  }

  @ViewBuilder
  private var actions: some View {
    VStack(spacing: 10) {
      if sharingExisting {
        primary("OK", .keepPersonal)
      } else {
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
