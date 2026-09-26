import SwiftUI
import SwiftData

struct MemoryRow: View {
  @Bindable var memory: MemoryModel
  var onMore: (() -> Void)? = nil
  var onTapImage: ((Int) -> Void)? = nil
  var onBlockUser: ((String) -> Void)? = nil
  /// Set by the Global feed. When true, a post matching `sensitiveTerms` renders blurred
  /// behind a tap-to-reveal. Off everywhere else — Home, the calendar and a memory's own
  /// day view are the author's journal, not a feed.
  var blursSensitiveContent: Bool = false
  var onDelete: (() -> Void)? = nil
  /// Set false inside `CommentThreadView` — you're already in the thread, and the
  /// button would push a second copy of it. Everything else (like, privacy, menu)
  /// stays live so the header card isn't inert.
  var showsCommentButton: Bool = true
  
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.modelContext) private var modelContext
  @Environment(\.colorScheme) private var scheme
  @State private var hasLiked = false
  @State private var likeTask: Task<Void, Never>? = nil
  @State private var isUpdatingPrivacy = false
  @State private var isBlocking = false
  @State private var showReportSheet = false
  @State private var selectedReportReason: ReportReason?
  @State private var isReporting = false
  @State private var reportConfirmed = false
  @State private var showDeleteConfirm = false
  @State private var showAuth = false
  /// Per-row and per-session on purpose: revealing one post is a decision about that
  /// post, not a standing preference to see everything.
  @State private var revealed = false
  @State private var isDeleting = false
  @State private var deleteError: String?
  
  // MARK: - Derived
  private var canEditPrivacy: Bool { auth.userID == memory.userID }

  /// Going Global requires a real account, exactly as it does on the Create screen.
  ///
  /// `CreateMemoryView` has gated this since the beginning, but the row's toggle wrote
  /// straight through to the model — so an anonymous user could publish to the Global
  /// feed simply by posting privately first and flipping the badge afterwards. The rule
  /// is about public posting, not about which screen you happen to be on.
  private var privacyBinding: Binding<Bool> {
    Binding(
      get: { memory.isPublic },
      set: { newValue in
        if newValue && auth.isGuest {
          showAuth = true
          return
        }
        if newValue && auth.isRestricted { return }
        memory.isPublic = newValue
      }
    )
  }

  /// Visibility is only changeable on the day the memory belongs to.
  ///
  /// The Global feed shows a single day and has no day picker, so publishing an older
  /// entry puts it somewhere nobody can look — the toggle appeared to work and did
  /// nothing. Limiting it to today also removes the awkward states: no re-uploading
  /// media for a day that has passed, and no post quietly changing visibility long
  /// after anyone saw it. Deleting an old memory is still fine; that's `canEditPrivacy`.
  private var canToggleVisibility: Bool {
    canEditPrivacy && Calendar.current.isDateInToday(memory.date)
  }
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
  
  /// Blur the body of this card? Never for the author's own post — it's their writing,
  /// and hiding it from them would be absurd.
  private var isConcealed: Bool {
    blursSensitiveContent
      && !revealed
      && auth.userID != memory.userID
      && (memory.isSensitive || ContentModeration.isSensitive(memory.journalText))
  }

  private var rowSummaryA11y: String {
    // A blurred post must stay hidden from VoiceOver too, or the reveal is a choice only
    // sighted readers get to make.
    if isConcealed {
      return "\(usernameLabel). \(createdAtA11y). Mood: \(moodLabel). Sensitive content, hidden. Likes: \(memory.likes)."
    }
    return "\(usernameLabel). \(createdAtA11y). Mood: \(moodLabel). \(mediaA11y) Likes: \(memory.likes). \(journalPreviewA11y)"
  }
  
  // MARK: - Body
  var body: some View {
    content
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      // Clip before the card modifier so full-bleed media follows the card's corner
      // radius, while the card's shadow (applied inside the modifier) stays outside.
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .premiumMoodCard(color: moodColor, isPremium: isPremium, scheme: scheme)
    
    // ✅ Make the whole row understandable as a single element…
      .accessibilityElement(children: .contain)
      .accessibilityLabel(rowSummaryA11y)
    
      .onAppear {
        if let uid = auth.userID {
          hasLiked = memory.likedBy.contains(uid)
        }
      }
      .sheet(isPresented: $showReportSheet) { reportSheet }
      .sheet(isPresented: $showAuth) {
        NavigationStack { AuthView() }
      }
      // A dialog rather than an alert: "un-share it" and "destroy it" are different
      // wishes, and a journal should not make someone delete a memory to stop sharing it.
      .confirmationDialog("Delete Post?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
        Button("Delete Everywhere", role: .destructive) { performDelete(scope: .everywhere) }
        Button("Remove from Cloud Only") { performDelete(scope: .remoteOnly) }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("\u{201C}Remove from Cloud\u{201D} takes this off the server and the Global feed but keeps your copy on this device. It won\u{2019}t sync to a new phone.")
      }
      .alert("Delete Failed", isPresented: Binding(
        get: { deleteError != nil },
        set: { if !$0 { deleteError = nil } }
      )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(deleteError ?? "")
      }
  }
}

// MARK: - Delete
private extension MemoryRow {
  func performDelete(scope: MemoryService.DeleteScope) {
    guard !isDeleting else { return }
    isDeleting = true
    Task {
      do {
        try await MemoryService.deleteMemory(memory, scope: scope, context: modelContext)
        await MainActor.run {
          // Only a full delete removes the row; a cloud-only delete leaves it on screen,
          // which is the visible proof that the local copy survived.
          if scope == .everywhere { onDelete?() }
          isDeleting = false
        }
      } catch {
        await MainActor.run {
          deleteError = error.localizedDescription
          isDeleting = false
        }
      }
    }
  }
}

// MARK: - Report sheet
private extension MemoryRow {
  var reportSheet: some View {
    ReportSheet(
      reportedUID: memory.userID,
      memoryID: memory.id,
      onBlock: onBlockUser,
      onDismiss: { showReportSheet = false }
    )
  }
}

struct ReportSheet: View {
  let reportedUID: String
  let memoryID: String
  var onBlock: ((String) -> Void)? = nil
  let onDismiss: () -> Void

  @State private var selectedReason: ReportReason?
  @State private var isSubmitting = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Why are you reporting this post?") {
          reasonRow(.inappropriate)
          reasonRow(.harassment)
          reasonRow(.spam)
          reasonRow(.hateSpeech)
          reasonRow(.other)
        }
      }
      .navigationTitle("Report Post")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel", action: onDismiss)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            guard let reason = selectedReason else { return }
            isSubmitting = true
            Task {
              try? await ReportService.report(
                reportedUID: reportedUID,
                memoryID: memoryID,
                reason: reason
              )
              await MainActor.run {
                isSubmitting = false
                onBlock?(reportedUID)
                onDismiss()
              }
            }
          } label: {
            if isSubmitting { ProgressView() } else { Text("Submit").bold() }
          }
          .disabled(selectedReason == nil || isSubmitting)
        }
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder
  private func reasonRow(_ reason: ReportReason) -> some View {
    Button { selectedReason = reason } label: {
      HStack {
        Text(reason.rawValue).foregroundStyle(.primary)
        Spacer()
        if selectedReason == reason {
          Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
        }
      }
    }
  }
}

// MARK: - Composition
private extension MemoryRow {
  /// Only the media is full-bleed; everything else keeps a text inset.
  /// `MemoryRow.body` supplies the vertical padding, so the photo can reach the
  /// card's left and right edges the way it does on Instagram/Facebook.
  static let textInset: CGFloat = 16

  var content: some View {
    VStack(alignment: .leading, spacing: 12) {
      headerRow
        .padding(.horizontal, Self.textInset)
      postBody
      actionRow
        .padding(.horizontal, Self.textInset)
    }
  }

  /// Text and media — the part a sensitive post blurs. The header stays readable so the
  /// reader knows whose post and which mood before deciding to reveal it.
  @ViewBuilder
  var postBody: some View {
    let stack = VStack(alignment: .leading, spacing: 12) {
      journalText
        .padding(.horizontal, Self.textInset)
      mediaSection
    }
    if isConcealed {
      stack
        // A one-line post blurs to a sliver too short to hold the reveal button.
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .blur(radius: 20)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay { revealButton }
    } else {
      stack
    }
  }

  var revealButton: some View {
    Button {
      withAnimation(.easeOut(duration: 0.25)) { revealed = true }
    } label: {
      VStack(spacing: 4) {
        Image(systemName: "eye.slash")
          .font(.title3)
        Text("Sensitive content")
          .font(.subheadline.weight(.semibold))
        Text("Tap to view")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Sensitive content")
    .accessibilityHint("Double tap to reveal this post.")
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
    if canEditPrivacy {
      Menu {
        Button(role: .destructive) {
          showDeleteConfirm = true
        } label: {
          Label("Delete Post", systemImage: "trash")
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(8)
          .contentShape(Rectangle())
      }
      .disabled(isDeleting)
      .accessibilityLabel("More options")
      .accessibilityHint("Shows actions for your post.")
    } else {
      Menu {
        Button {
          showReportSheet = true
        } label: {
          Label("Report Post", systemImage: "flag")
        }

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

    if let audio = memory.audioSource {
      // Audio stays inset — it's a transport control, not a photo.
      MediaTile(source: audio, cornerRadius: cornerRadius, minHeight: 80, accentColor: moodColor)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .padding(.horizontal, Self.textInset)
        .accessibilityLabel("Voice note.")
        .accessibilityHint("Double tap to play or pause.")

    } else if let video = memory.videoSource {
      // Full-bleed 16:9, matching how video reads in a social feed.
      Color.clear
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .overlay {
          MediaTile(source: video, cornerRadius: 0, minHeight: 0)
        }
        .clipped()
      // ✅ Media is actionable / informative — label it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Video attachment.")
        .accessibilityHint("Double tap to play the video.")

    } else if !memory.imageSources.isEmpty {
      // Edge-to-edge 4:5. MediaBlock owns its own sizing and paging now.
      MediaBlock(sources: memory.imageSources, onTap: onTapImage)
      // ✅ Let VO know how many images & what to do
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
      .padding(.horizontal, Self.textInset)
      // ✅ Link should be announced clearly
      .accessibilityLabel("Link attachment.")
      .accessibilityHint("Opens in your browser.")
    }
  }
  
  // 5) Actions
  var actionRow: some View {
    HStack(spacing: 12) {
      likeButton
      if showsCommentButton { commentButton }
      Spacer()
      if canToggleVisibility {
        PrivacyBadge(isPublic: privacyBinding)
          .disabled(isUpdatingPrivacy)
          .accessibilityLabel("Privacy")
          .accessibilityValue(memory.isPublic ? "Global" : "Personal")
          .accessibilityHint("Double tap to change visibility.")
          .onChange(of: memory.isPublic) { _, newValue in
            guard !isUpdatingPrivacy else { return }
            isUpdatingPrivacy = true
            Task {
              do {
                try await MemoryService.updatePrivacy(for: memory, isPublic: newValue)
                // The World feed holds cached DTOs that would otherwise re-upsert the
                // old value straight back over this one.
                NotificationCenter.default.post(
                  name: .memoryPrivacyDidChange,
                  object: nil,
                  userInfo: ["id": memory.id, "isPublic": newValue]
                )
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
      // Optimistic UI update
      hasLiked.toggle()
      memory.likes += hasLiked ? 1 : -1

      // Cancel any pending write and schedule a new one after 800ms.
      // If the user taps again before the delay fires, only the final
      // state is written — preventing rapid back-and-forth Firestore calls.
      likeTask?.cancel()
      likeTask = Task {
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        do {
          try await MemoryService.toggleLike(memory: memory)
        } catch {
          // Roll back on failure
          await MainActor.run {
            hasLiked.toggle()
            memory.likes += hasLiked ? 1 : -1
          }
          print("⚠️ Failed to toggle like:", error)
        }
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: hasLiked ? "heart.fill" : "heart")
          .accessibilityHidden(true)
        Text("\(max(0, memory.likes))")
          .font(.caption.weight(.semibold))
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Capsule().fill(hasLiked ? Color.pink.opacity(0.15) : moodColor.opacity(0.12)))
      .foregroundStyle(hasLiked ? Color.pink : .secondary)
      .animation(.easeInOut(duration: 0.15), value: hasLiked)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(hasLiked ? "Liked" : "Like")
    .accessibilityValue("\(memory.likes) likes")
    .accessibilityHint(hasLiked ? "Tap to unlike." : "Tap to like.")
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