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
    // Keep this short so VO doesn’t read an entire essay in the feed.
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
      privacyBadgeRow
      userDateRow
      headerCard
      journalText
      mediaSection
      actionRow
    }
    .padding(.horizontal, 12)
  }
}

// MARK: - Subsections
private extension MemoryRow {
  
  // 0) Privacy badge (owner only) OR More menu (others)
  var privacyBadgeRow: some View {
    Group {
      HStack {
        Spacer()
        
        if canEditPrivacy {
          PrivacyBadge(isPublic: $memory.isPublic)
            .disabled(isUpdatingPrivacy)
          
          // ✅ Clear toggle semantics
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
          
        } else {
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
            Image(systemName: "ellipsis.circle")
              .imageScale(.large)
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(memory.mood.adaptiveColor)
              .padding(.vertical, 4)
          }
          .disabled(isBlocking)
          .animation(.default, value: isBlocking)
          
          // ✅ Menu button should speak like “More options”
          .accessibilityLabel("More options")
          .accessibilityHint("Shows actions for \(usernameLabel).")
          .accessibilityValue(isBlocking ? "Busy" : "")
        }
      }
    }
  }
  
  // 2) Username + date
  var userDateRow: some View {
    HStack {
      if memory.isPremium,
         let urlString = memory.remoteProfilePhotoURL,
         let url = URL(string: urlString) {
        AsyncImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
              .frame(width: 32, height: 32)
              .clipShape(Circle())
              .accessibilityHidden(true) // ✅ decorative; username provides identity
          case .failure:
            MoodIcon(mood: memory.mood, size: 20).opacity(0.9)
              .accessibilityHidden(true)
          case .empty:
            ProgressView()
              .frame(width: 20, height: 20)
              .accessibilityLabel("Loading profile image")
          @unknown default:
            MoodIcon(mood: memory.mood, size: 20).opacity(0.9)
              .accessibilityHidden(true)
          }
        }
      } else {
        MoodIcon(mood: memory.mood, size: 20).opacity(0.9)
          .accessibilityHidden(true) // ✅ mood is spoken elsewhere
      }
      
      Text("@\(memory.username)")
        .font(.subheadline.weight(.semibold))
      
      Spacer()
      
      Text(timeString)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    // ✅ Read this row cleanly as one sentence
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(usernameLabel). \(createdAtA11y).")
  }
  
  // 1) Header (“TodayI felt …”)
  var headerCard: some View {
    HStack(alignment: .center, spacing: 12) {
      Text("TodayI felt")
        .font(.subheadline.bold())
        .foregroundStyle(.secondary)
        .accessibilityHidden(true) // we provide a combined label below
      
      moodChip
        .accessibilityHidden(true)
      
      Spacer(minLength: 0)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(headerBackground.accessibilityHidden(true)) // gradients/strokes are decorative
    
    // ✅ Speak as one logical statement
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Mood: \(memory.mood.rawValue).")
  }
  
  var moodChip: some View {
    Group {
      if isPremium {
        Text(memory.mood.rawValue)
          .font(.headline.bold())
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(Capsule().fill(Color(.systemBackground).opacity(0.85)))
          .foregroundStyle(moodColor)
          .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
      } else {
        Text(memory.mood.rawValue)
          .font(.headline.bold())
          .foregroundStyle(moodColor)
      }
    }
  }
  
  var headerBackground: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(isPremium ? Color.white.opacity(0.08) : moodColor.opacity(0.15))
      .overlay(
        Group {
          if isPremium {
            LinearGradient(
              colors: [moodColor.opacity(0.20), moodColor.opacity(0.08)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(moodColor.opacity(isPremium ? 0.18 : 0.15), lineWidth: 1)
      )
  }
  
  // 3) Journal text
  var journalText: some View {
    Group {
      if !memory.journalText.isEmpty {
        Text(memory.journalText)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        // ✅ Keep default reading (it’s the actual content)
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
      MediaTile(source: audio, cornerRadius: cornerRadius, minHeight: 80)
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
  
  // 5) Actions / flags
  var actionRow: some View {
    HStack(spacing: 16) {
      likeButton
      commentButton
        .frame(width: 60)
      Spacer()
      PremiumPill(isPremium: isPremium)
      // ✅ If you want it read:
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPremium ? "Premium post" : "Standard post")
    }
    .font(.subheadline.weight(.semibold))
    .padding(.top, 6)
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
      HStack(spacing: 6) {
        Image(systemName: hasLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
          .accessibilityHidden(true) // we provide a full label below
        Text("\(memory.likes)")
          .font(.caption.weight(.semibold))
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        Capsule().fill(
          hasLiked
          ? moodColor.opacity(0.3)
          : moodColor.opacity(0.15)
        )
      )
      .foregroundStyle(hasLiked ? moodColor : .secondary)
    }
    .buttonStyle(.plain)
    .disabled(hasLiked)
    
    // ✅ Proper control semantics
    .accessibilityLabel(hasLiked ? "Liked" : "Like")
    .accessibilityValue("\(memory.likes) likes")
    .accessibilityHint(hasLiked ? "Already liked." : "Adds one like.")
  }
  
  var commentButton: some View {
    NavigationLink {
      CommentThreadView(memory: memory)
    } label: {
      Image(systemName: "text.bubble.fill")
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(moodColor.opacity(0.18)))
        .foregroundStyle(moodColor)
    }
    .buttonStyle(.plain)
    
    // ✅ Navigation intent
    .accessibilityLabel("Comments")
    .accessibilityHint("Opens the comment thread.")
  }
}
