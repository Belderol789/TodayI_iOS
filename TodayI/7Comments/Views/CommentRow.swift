import SwiftUI

struct CommentRow: View {
  let memoryID: String
  let comment: CommentDTO
  let dataManager: SwiftDataManager
  let auth: AuthStore

  let onDeleted: (String) -> Void
  let onBlocked: (String) -> Void

  @State private var showAlert = false
  @State private var isBlocking = false

  private var isOwn: Bool { comment.userID == auth.userID }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      avatar
      bubble
      if isOwn { moreMenu }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
  }
}

// MARK: - Subviews
private extension CommentRow {
  var avatar: some View {
    Circle()
      .fill(Color.secondary.opacity(0.15))
      .frame(width: 32, height: 32)
      .overlay(
        Text(String(comment.username.prefix(1)).uppercased())
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
      )
  }

  var bubble: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text("@\(comment.username)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isOwn ? Color.accentColor : .primary)
        Text(comment.createdAt, style: .relative)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .fixedSize()
      }
      Text(comment.text)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(isOwn ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
    )
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  var moreMenu: some View {
    Menu {
      Button(role: .destructive) { showAlert = true } label: {
        Label("Delete", systemImage: "trash")
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(6)
    }
    .alert("Delete Comment?", isPresented: $showAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) { deleteComment() }
    } message: {
      Text("This comment will be permanently deleted.")
    }
  }
}

// MARK: - Others' menu (long-press)
extension CommentRow {
  // Applied in CommentThreadView via .contextMenu on the row
  var contextActions: some View {
    Group {
      if !isOwn {
        Button(role: .destructive) { showAlert = true } label: {
          Label("Block \("@\(comment.username)")", systemImage: "hand.raised.fill")
        }
      }
    }
    .alert("Block @\(comment.username)?", isPresented: $showAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Block", role: .destructive) { blockUser() }
    } message: {
      Text("Their comments will be hidden from you.")
    }
  }
}

// MARK: - Logic
private extension CommentRow {
  func blockUser() {
    guard !isBlocking, !comment.userID.isEmpty else { return }
    isBlocking = true
    dataManager.addBlockedUser(comment.userID)
    onBlocked(comment.userID)
    isBlocking = false
  }

  func deleteComment() {
    Task {
      do {
        try await MemoryService.deleteComment(memoryID: memoryID, commentID: comment.id)
        await MainActor.run { onDeleted(comment.id) }
      } catch {
        print("❌ Failed to delete comment:", error)
      }
    }
  }
}
