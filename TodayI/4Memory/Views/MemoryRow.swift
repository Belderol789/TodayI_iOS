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
  
  // MARK: - Body (now tiny!)
  var body: some View {
    content
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .premiumMoodCard(color: moodColor, isPremium: isPremium, scheme: scheme)
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
                onBlockUser?(memory.userID)            // ⬅️ instantly purge from UI
              }
            } label: {
              Label("Block @\(memory.username)", systemImage: "hand.raised.fill")
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
              .frame(width: 20, height: 20)
              .clipShape(Circle())
          case .failure:
            MoodIcon(mood: memory.mood, size: 20).opacity(0.9)
          case .empty:
            ProgressView()
              .frame(width: 20, height: 20)
          @unknown default:
            MoodIcon(mood: memory.mood, size: 20).opacity(0.9)
          }
        }
      } else {
        MoodIcon(mood: memory.mood, size: 20).opacity(0.9)
      }
      
      Text("@\(memory.username)")
        .font(.subheadline.weight(.semibold))
      
      Spacer()
      
      Text(timeString)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
  
  // 1) Header (“TodayI felt …” with capsule or color text) + menu
  var headerCard: some View {
    HStack(alignment: .center, spacing: 12) {
      Text("TodayI felt")
        .font(.subheadline.bold())
        .foregroundStyle(.secondary)
      moodChip
      Spacer(minLength: 0)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(headerBackground)
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
      }
    }
  }
  
  // 4) Media (video -> images -> link)
  // MARK: - 4) Media (video → images → link)
  @ViewBuilder
  var mediaSection: some View {
    let cornerRadius: CGFloat = 14
    let cardPadding: CGFloat = 14
    
    if let video = memory.videoSource {
      // --- VIDEO TILE ---
      Color.clear
        .frame(height: 220) // reserve layout height
        .overlay {
          MediaTile(source: video, cornerRadius: cornerRadius, minHeight: 220)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: isPremium ? moodColor.opacity(0.12) : .clear,
                    radius: isPremium ? 10 : 0, x: 0, y: 6)
            .padding(.horizontal, -cardPadding) // visual bleed
        }
        .clipped() // ⛔ clamp any overflow to the row’s bounds
      
    } else if !memory.imageSources.isEmpty {
      // --- IMAGE BLOCK ---
      // If your MediaBlock has dynamic height, replace 220 with that value.
      Color.clear
        .frame(height: 220)
        .overlay {
          MediaBlock(sources: memory.imageSources, onTap: onTapImage)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: isPremium ? moodColor.opacity(0.12) : .clear,
                    radius: isPremium ? 10 : 0, x: 0, y: 6)
            .padding(.horizontal, -cardPadding) // visual bleed
        }
        .clipped() // ⛔ clamp bleed so it can’t extend past the body
      
    } else if let urlString = memory.linkURL,
              !urlString.isEmpty,
              let url = URL(string: urlString) {
      // --- LINK PREVIEW (no bleed needed) ---
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
    }
    .font(.subheadline.weight(.semibold))
    .padding(.top, 6)
  }
  
  var likeButton: some View {
    Button {
      guard !hasLiked else { return } // prevent double-like in UI
      hasLiked = true
      memory.likes += 1 // ✅ instantly reflect change in UI
      
      Task {
        do {
          try await MemoryService.like(memory: memory)
        } catch {
          print("⚠️ Failed to like post:", error)
          hasLiked = false
          memory.likes -= 1 // rollback UI on failure
        }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: hasLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
        Text("\(memory.likes)")
          .font(.caption.weight(.semibold))
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
  }
}
