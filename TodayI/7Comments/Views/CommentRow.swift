import SwiftUI

struct CommentRow: View {
  let memoryID: String
  let comment: CommentDTO
  let dataManager: SwiftDataManager
  let auth: AuthStore
  /// The mood of the memory this thread belongs to — used as the avatar when the
  /// commenter has no profile photo. A commenter's *own* mood isn't available here:
  /// their `dates/{dayKey}` is owner-read-only and their memories are only readable
  /// when public, so per-commenter moods would need rules changes and a read each.
  let mood: Mood

  let onDeleted: (String) -> Void
  let onBlocked: (String) -> Void

  @State private var showAlert = false
  @State private var isBlocking = false

  private var isOwn: Bool { comment.userID == auth.userID }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      avatar
      bubble
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
  }
}

// MARK: - Subviews
private extension CommentRow {
  /// Photo if we have one, otherwise the memory's mood icon — same fallback shape
  /// `MemoryRow.avatar` uses, so a thread reads as one piece with its card.
  @ViewBuilder
  var avatar: some View {
    if let urlString = comment.photoURL, let url = URL(string: urlString) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill()
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        case .empty:
          Circle().fill(Color(.systemGray5)).frame(width: 32, height: 32)
            .overlay(ProgressView().scaleEffect(0.5))
        default:
          moodAvatar
        }
      }
    } else {
      moodAvatar
    }
  }

  var moodAvatar: some View {
    Circle()
      .fill(mood.adaptiveColor.opacity(0.18))
      .frame(width: 32, height: 32)
      .overlay(MoodIcon(mood: mood, size: 16).opacity(0.9))
      .accessibilityHidden(true)
  }

  var bubble: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text("@\(comment.username)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isOwn ? Color.accentColor : .primary)
        Text(comment.createdAt.formatted(date: .omitted, time: .shortened))
          .font(.caption2)
          .foregroundStyle(.tertiary)
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
    .contextMenu {
      if isOwn {
        Button(role: .destructive) { showAlert = true } label: {
          Label("Delete Comment", systemImage: "trash")
        }
      } else {
        Button(role: .destructive) { showAlert = true } label: {
          Label("Block @\(comment.username)", systemImage: "hand.raised.fill")
        }
      }
    }
    .alert(isOwn ? "Delete Comment?" : "Block @\(comment.username)?",
           isPresented: $showAlert) {
      Button("Cancel", role: .cancel) {}
      Button(isOwn ? "Delete" : "Block", role: .destructive) {
        isOwn ? deleteComment() : blockUser()
      }
    } message: {
      Text(isOwn ? "This comment will be permanently deleted."
                 : "Their comments will be hidden from you.")
    }
  }
}

// MARK: - Logic
private extension CommentRow {
  func blockUser() {
    guard !isBlocking, !comment.userID.isEmpty else { return }
    isBlocking = true
    Task { await dataManager.addBlockedUser(comment.userID) }
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
