import SwiftUI
import FirebaseFirestore

struct CommentThreadView: View {
  let memory: MemoryModel
  @StateObject private var vm: CommentThreadViewModel
  @Environment(\.swiftDataManager) private var swiftManager
  @EnvironmentObject private var auth: AuthStore
  
  @State private var blockedUserIDs: Set<String> = []
  
  init(memory: MemoryModel) {
    self.memory = memory
    _vm = StateObject(wrappedValue: CommentThreadViewModel(memoryID: memory.id))
  }
  
  var body: some View {
    VStack(spacing: 0) {
      scrollArea
      Divider()
      commentBox
    }
    .navigationTitle("Comments")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await vm.loadComments()
      if let manager = swiftManager {
        blockedUserIDs = Set(manager.fetchBlockedUsers())
      }
    }
    .onChange(of: swiftManager?.fetchBlockedUsers() ?? []) { latest in
      blockedUserIDs = Set(latest)
    }
  }
}

// MARK: - Subviews

private extension CommentThreadView {
  @ViewBuilder
  var scrollArea: some View {
    ScrollViewReader { _ in
      ScrollView {
        VStack(spacing: 16) {
          MemoryRow(memory: memory)
            .padding(.horizontal)
            .padding(.top, 8)
          
          Divider()
          
          commentsSection
        }
      }
    }
  }
  
  @ViewBuilder
  var commentsSection: some View {
    if vm.isLoading {
      ProgressView("Loading comments…")
        .padding(.top, 40)
    } else {
      let visible = visibleComments
      if visible.isEmpty {
        Text("No comments yet.")
          .foregroundStyle(.secondary)
          .padding(.top, 40)
      } else {
        commentsList(visible)
      }
    }
  }
  
  @ViewBuilder
  func commentsList(_ comments: [CommentDTO]) -> some View {
    ForEach(comments) { comment in
      commentRow(for: comment)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
  }
  
  @ViewBuilder
  func commentRow(for comment: CommentDTO) -> some View {
    // Avoid force-unwrapping the manager; if missing, pass a stub or early-exit
    if let manager = swiftManager {
      CommentRow(
        memoryID: memory.id,
        comment: comment,
        dataManager: manager,
        auth: auth,
        onDeleted: handleDeleted(id:),
        onBlocked: handleBlocked(userID:)
      )
    } else {
      EmptyView()
    }
  }
}

// MARK: - Actions

private extension CommentThreadView {
  func handleDeleted(id: String) {
    if let idx = vm.comments.firstIndex(where: { $0.id == id }) {
      vm.comments.remove(at: idx)
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

// MARK: - Input Bar (unchanged from your version)

private extension CommentThreadView {
  var commentBox: some View {
    HStack(alignment: .center, spacing: 8) {
      ZStack(alignment: .topLeading) {
        if vm.newComment.isEmpty {
          Text("Add a comment…")
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .allowsHitTesting(false)
        }
        
        TextEditor(text: $vm.newComment)
          .scrollContentBackground(.hidden)
          .background(.clear)
          .padding(.vertical, 8)
          .padding(.horizontal, 8)
          .frame(minHeight: 36, maxHeight: 120)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
          )
      }
      
      Button {
        Task { await vm.postComment() }
      } label: {
        Image(systemName: "paperplane.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(vm.newComment.isEmpty ? .secondary : .accentColor)
          .padding(.horizontal, 4)
      }
      .disabled(vm.newComment.isEmpty)
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial)
  }
}
