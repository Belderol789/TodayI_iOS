import SwiftUI
import FirebaseFirestore

struct CommentThreadView: View {
  let memory: MemoryModel
  @StateObject private var vm: CommentThreadViewModel
  @Environment(\.swiftDataManager) private var swiftManager
  @EnvironmentObject private var auth: AuthStore

  @State private var showSetting = false
  @State private var blockedUserIDs: Set<String> = []
  @FocusState private var inputFocused: Bool
  @Namespace private var bottomAnchor

  init(memory: MemoryModel) {
    self.memory = memory
    _vm = StateObject(wrappedValue: CommentThreadViewModel(memoryID: memory.id))
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          memoryPreview
            .padding(.bottom, 8)

          Divider()
            .padding(.horizontal, 16)

          commentsSection

          Color.clear.frame(height: 1).id("bottom")
        }
        .padding(.top, 8)
      }
      .onChange(of: vm.comments.count) { _, _ in
        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
      }
    }
    .navigationTitle("Comments")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
    .onAppear { auth.hideTabBar = true }
    .onDisappear { auth.hideTabBar = false }
    .task {
      await vm.loadComments()
      if let manager = swiftManager {
        blockedUserIDs = Set(manager.fetchBlockedUsers())
      }
    }
    .sheet(isPresented: $showSetting) {
      NavigationStack { AuthView() }
    }
  }
}

// MARK: - Memory preview
private extension CommentThreadView {
  var memoryPreview: some View {
    // Interactive: `allowsHitTesting(false)` here used to disable the privacy toggle
    // and the like button along with everything else. Only the comment button is
    // dropped, since tapping it from inside the thread would just push another one.
    MemoryRow(memory: memory, showsCommentButton: false)
      .padding(.horizontal, 16)
  }
}

// MARK: - Comments
private extension CommentThreadView {
  @ViewBuilder
  var commentsSection: some View {
    if vm.isLoading {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    } else {
      let visible = visibleComments
      if visible.isEmpty {
        emptyState
      } else {
        LazyVStack(spacing: 2) {
          loadMoreHeader
          ForEach(visible) { comment in
            commentRow(for: comment)
          }
        }
        .padding(.top, 12)
      }
    }
  }

  var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 36))
        .foregroundStyle(.tertiary)
      Text("No comments yet")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
      Text("Be the first to say something.")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 48)
  }

  @ViewBuilder
  var loadMoreHeader: some View {
    if vm.isLoadingMore {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    } else if !vm.reachedEnd {
      Button {
        Task { await vm.loadMore() }
      } label: {
        Text("Load earlier comments")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
    }
  }

  @ViewBuilder
  func commentRow(for comment: CommentDTO) -> some View {
    if let manager = swiftManager {
      CommentRow(
        memoryID: memory.id,
        comment: comment,
        dataManager: manager,
        auth: auth,
        mood: memory.mood,
        onDeleted: handleDeleted(id:),
        onBlocked: handleBlocked(userID:)
      )
    }
  }
}

// MARK: - Input bar
private extension CommentThreadView {
  @ViewBuilder
  var inputBar: some View {
    if auth.isGuest {
      AuthRequiredView { showSetting = true }
        .background(.ultraThinMaterial)
    } else {
      VStack(alignment: .trailing, spacing: 4) {
        // Only appears as the cap gets close, so the bar stays clean normally.
        if vm.remaining <= 100 {
          Text("\(vm.remaining)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(vm.remaining == 0 ? Color.red : Color.secondary)
            .accessibilityLabel("\(vm.remaining) characters remaining")
        }

        HStack(alignment: .bottom, spacing: 10) {
          // Matches CommentRow's avatar so your draft looks like your posted comment.
          composerAvatar

          ZStack(alignment: .leading) {
            if vm.newComment.isEmpty {
              Text("Add a comment…")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
                .allowsHitTesting(false)
            }
            TextField("", text: $vm.newComment, axis: .vertical)
              .font(.subheadline)
              .lineLimit(1...5)
              .focused($inputFocused)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .fill(Color(.secondarySystemBackground))
          )

          Button {
            Task { await vm.postComment(username: auth.username, photoURL: auth.photoURL) }
            inputFocused = false
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.system(size: 28))
              .foregroundStyle(vm.newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                               ? Color.secondary : Color.accentColor)
          }
          .disabled(vm.newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .animation(.easeInOut(duration: 0.15), value: vm.newComment.isEmpty)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(.ultraThinMaterial)
      .animation(.easeInOut(duration: 0.15), value: vm.remaining <= 100)
    }
  }
}

// MARK: - Composer avatar
private extension CommentThreadView {
  /// Your own cached profile image first, then your remote photo, then the memory's
  /// mood icon — the same fallback order `CommentRow` uses.
  @ViewBuilder
  var composerAvatar: some View {
    if let image = auth.profileImage {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    } else if let urlString = auth.photoURL, let url = URL(string: urlString) {
      AsyncImage(url: url) { phase in
        if case .success(let image) = phase {
          image.resizable().scaledToFill()
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
          moodAvatar
        }
      }
    } else {
      moodAvatar
    }
  }

  var moodAvatar: some View {
    Circle()
      .fill(memory.mood.adaptiveColor.opacity(0.18))
      .frame(width: 32, height: 32)
      .overlay(MoodIcon(mood: memory.mood, size: 16).opacity(0.9))
      .accessibilityHidden(true)
  }
}

// MARK: - Actions
private extension CommentThreadView {
  func handleDeleted(id: String) {
    withAnimation(.easeOut(duration: 0.2)) {
      vm.comments.removeAll { $0.id == id }
    }
  }

  func handleBlocked(userID: String) {
    blockedUserIDs.insert(userID)
  }
}

// MARK: - Derived
private extension CommentThreadView {
  var visibleComments: [CommentDTO] {
    vm.comments.filter { !blockedUserIDs.contains($0.userID) }
  }
}
