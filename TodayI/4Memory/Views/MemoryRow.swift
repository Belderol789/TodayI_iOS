import SwiftUI
import SwiftData

struct MemoryRow: View {
  @Bindable var memory: MemoryModel
  var onMore: (() -> Void)? = nil
  var onTapImage: ((Int) -> Void)? = nil
  var onBlockUser: ((String) -> Void)? = nil
  
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.colorScheme) private var scheme
  @State private var hasLiked = false
  @State private var isUpdatingPrivacy = false
  @State private var isBlocking = false
  
  // MARK: - Derived
  private var canEditPrivacy: Bool { auth.userID == memory.userID }
  private var timeString: String { DateFormatter.shortDateFormatter.string(from: memory.createdAt) }
  private var isPremium: Bool { memory.isPremium }
  private var moodColor: Color { memory.mood.adaptiveColor }
  
  // ✅ Accessibility helpers
  private var usernameLabel: String { "@\(memory.username)" }
  private var createdAtA11y: String {
    memory.createdAt.formatted(.dateTime.month(.wide).day().year())
  }
  private var moodLabel: String { memory.mood.rawValue }
  
  private var journalPreviewA11y: String {
    let trimmed = memory.journalText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "No journal text." }
    // Keep this short so VO doesn't read an entire essay in the feed.
    let max = 140
    if trimmed.count <= max { return trimmed }
    let idx = trimmed.index(trimmed.startIndex, offsetBy: max)
    return String(trimmed[..<idx]) + "…"
  }
  
  private var mediaA11y: String {
    if memory.audioSource != nil { return "Contains a voice note." }
    if memory.videoSource != nil { return "Contains a video." }
    if !memory.imageSources.isEmpty { return "Contains \(memory.imageSources.count) image\(memory.imageSources.count == 1 ? "" : "s")." }
    if let link = memory.linkURL, !link.isEmpty { return "Contains a link." }
    return "No media."
  }
  
  private var rowSummaryA11y: String {
    "\(usernameLabel). \(createdAtA11y). Mood: \(moodLabel). \(mediaA11y) Likes: \(memory.likes). \(journalPreviewA11y)"
  }
  
  // MARK: - Body
  var body: some View {
    content
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .premiumMoodCard(color: moodColor, isPremium: isPremium, scheme: scheme)
    
    // ✅ Make the whole row understandable as a single element…
      .accessibilityElement(children: .contain)
      .accessibilityLabel(rowSummaryA11y)
    
      .onAppear {
        if memory.userID == auth.userID {
          hasLiked = true
          memory.likes = memory.likes == 0 ? 1 : memory.likes
        }
      }
  }
}

// MARK: - Composition
private extension MemoryRow {
  var content: some View {
    VStack(alignment: .leading, spacing: 12) {
      headerRow
      journalText
      mediaSection
      actionRow
    }
    .padding(.horizontal, 12)
  }
}

// MARK: - Subsections
private extension MemoryRow {
  
  // Header: avatar · [username + mood chip / date] · trailing action
  var headerRow: some View {
    HStack(alignment: .top, spacing: 10) {
      avatar
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text("@\(memory.username)")
            .font(.subheadline.weight(.semibold))
          moodChip
          Spacer(minLength: 0)
        }
        Text(timeString)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      trailingAction
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(usernameLabel). Mood: \(moodLabel). \(createdAtA11y).")
  }

  @ViewBuilder
  var avatar: some View {
    if memory.isPremium,
       let urlString = memory.remoteProfilePhotoURL,
       let url = URL(string: urlString) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill()
            .frame(width: 36, height: 36).clipShape(Circle())
        case .empty:
          Circle().fill(Color(.systemGray5)).frame(width: 36, height: 36)
            .overlay(ProgressView().scaleEffect(0.6))
        default:
          moodIconAvatar
        }
      }
    } else {
      moodIconAvatar
    }
  }

  var moodIconAvatar: some View {
    Circle()
      .fill(moodColor.opacity(0.18))
      .frame(width: 36, height: 36)
      .overlay(MoodIcon(mood: memory.mood, size: 18).opacity(0.9))
  }

  var moodChip: some View {
    Text(memory.mood.rawValue)
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Capsule().fill(moodColor.opacity(0.15)))
      .foregroundStyle(moodColor)
  }

  @ViewBuilder
  var trailingAction: some View {
    if !canEditPrivacy {
      Menu {
        Button(role: .destructive) {
          guard !isBlocking else { return }
          isBlocking = true
          Task { @MainActor in
            defer { isBlocking = false }
            onBlockUser?(memory.userID)
          }
        } label: {
          Label("Block \(usernameLabel)", systemImage: "hand.raised.fill")
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(8)
          .contentShape(Rectangle())
      }
      .disabled(isBlocking)
      .accessibilityLabel("More options")
      .accessibilityHint("Shows actions for \(usernameLabel).")
      .accessibilityValue(isBlocking ? "Busy" : "")
    }
  }
  
  // 3) Journal text
  var journalText: some View {
    Group {
      if !memory.journalText.isEmpty {
        Text(memory.journalText)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        // ✅ Keep default reading (it's the actual content)
          .accessibilityLabel(memory.journalText)
      }
    }
  }
  
  // 4) Media (video -> images -> audio -> link)
  @ViewBuilder
  var mediaSection: some View {
    let cornerRadius: CGFloat = 14
    let cardPadding: CGFloat = 14

    if let audio = memory.audioSource {
      MediaTile(source: audio, cornerRadius: cornerRadius, minHeight: 80, accentColor: moodColor)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel("Voice note.")
        .accessibilityHint("Double tap to play or pause.")

    } else if let video = memory.videoSource {
      Color.clear
        .frame(height: 220)
        .overlay {
          MediaTile(source: video, cornerRadius: cornerRadius, minHeight: 220)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: isPremium ? moodColor.opacity(0.12) : .clear,
                    radius: isPremium ? 10 : 0, x: 0, y: 6)
            .padding(.horizontal, -cardPadding)
        }
        .clipped()
      // ✅ Media is actionable / informative — label it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Video attachment.")
        .accessibilityHint("Double tap to play the video.")
      
    } else if !memory.imageSources.isEmpty {
      Color.clear
        .frame(height: 220)
        .overlay {
          MediaBlock(sources: memory.imageSources, onTap: onTapImage)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: isPremium ? moodColor.opacity(0.12) : .clear,
                    radius: isPremium ? 10 : 0, x: 0, y: 6)
            .padding(.horizontal, -cardPadding)
        }
        .clipped()
      // ✅ Let VO know how many images & what to do
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(memory.imageSources.count) image attachment\(memory.imageSources.count == 1 ? "" : "s").")
        .accessibilityHint("Double tap an image to view it full screen.")
      
    } else if let urlString = memory.linkURL,
              !urlString.isEmpty,
              let url = URL(string: urlString) {
      Link(destination: url) {
        LinkPreviewView(url: url)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: 160)
          .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
          .shadow(color: isPremium ? moodColor.opacity(0.12) : .clear,
                  radius: isPremium ? 10 : 0, x: 0, y: 6)
      }
      .buttonStyle(.plain)
      // ✅ Link should be announced clearly
      .accessibilityLabel("Link attachment.")
      .accessibilityHint("Opens in your browser.")
    }
  }
  
  // 5) Actions
  var actionRow: some View {
    HStack(spacing: 12) {
      likeButton
      commentButton
      Spacer()
      if canEditPrivacy {
        PrivacyBadge(isPublic: $memory.isPublic)
          .disabled(isUpdatingPrivacy)
          .accessibilityLabel("Privacy")
          .accessibilityValue(memory.isPublic ? "Public" : "Private")
          .accessibilityHint("Double tap to change visibility.")
          .onChange(of: memory.isPublic) { _, newValue in
            guard !isUpdatingPrivacy else { return }
            isUpdatingPrivacy = true
            Task {
              do {
                try await MemoryService.updatePrivacy(for: memory, isPublic: newValue)
              } catch {
                print("⚠️ Failed to update privacy:", error)
              }
              isUpdatingPrivacy = false
            }
          }
      }
    }
    .padding(.top, 4)
  }

  var likeButton: some View {
    Button {
      guard !hasLiked else { return }
      hasLiked = true
      memory.likes += 1
      Task {
        do {
          try await MemoryService.like(memory: memory)
        } catch {
          print("⚠️ Failed to like post:", error)
          hasLiked = false
          memory.likes -= 1
        }
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: hasLiked ? "heart.fill" : "heart")
          .accessibilityHidden(true)
        Text("\(memory.likes)")
          .font(.caption.weight(.semibold))
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Capsule().fill(hasLiked ? Color.pink.opacity(0.15) : moodColor.opacity(0.12)))
      .foregroundStyle(hasLiked ? Color.pink : .secondary)
    }
    .buttonStyle(.plain)
    .disabled(hasLiked)
    .accessibilityLabel(hasLiked ? "Liked" : "Like")
    .accessibilityValue("\(memory.likes) likes")
    .accessibilityHint(hasLiked ? "Already liked." : "Adds one like.")
  }

  var commentButton: some View {
    NavigationLink {
      CommentThreadView(memory: memory)
    } label: {
      HStack(spacing: 5) {
        Image(systemName: "bubble.right")
          .accessibilityHidden(true)
        Text("Reply")
          .font(.caption.weight(.semibold))
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Capsule().fill(moodColor.opacity(0.12)))
      .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Comments")
    .accessibilityHint("Opens the comment thread.")
  }
}
