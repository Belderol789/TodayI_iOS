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
    .toolbar(.hidden, for: .tabBar)
    .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
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
    MemoryRow(memory: memory)
      .padding(.horizontal, 16)
      .allowsHitTesting(false)  // preview only — actions disabled
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
        onDeleted: handleDeleted(id:),
        onBlocked: handleBlocked(userID:)
      )
      .contextMenu {
        if comment.userID != auth.userID {
          Button(role: .destructive) {
            manager.addBlockedUser(comment.userID)
            handleBlocked(userID: comment.userID)
          } label: {
            Label("Block @\(comment.username)", systemImage: "hand.raised.fill")
          }
        }
      }
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
      HStack(alignment: .bottom, spacing: 10) {
        Circle()
          .fill(Color.secondary.opacity(0.15))
          .frame(width: 32, height: 32)
          .overlay(
            Text(String((auth.username ?? "?").prefix(1)).uppercased())
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
          )

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
          Task { await vm.postComment(username: auth.username) }
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
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(.ultraThinMaterial)
    }
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
