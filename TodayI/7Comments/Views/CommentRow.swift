import SwiftUI

struct CommentRow: View {
  
  let memoryID: String
  let comment: CommentDTO
  let dataManager: SwiftDataManager
  let auth: AuthStore   // Injected dependency
  
  let onDeleted: (String) -> Void
  let onBlocked: (String) -> Void
  
  @State private var showAlert = false
  @State private var isBlocking = false
  
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      avatarSection
      commentContent
    }
    .padding(.vertical, 6)
  }
}

extension CommentRow {
  // MARK: - Avatar
  private var avatarSection: some View {
    Circle()
      .fill(Color.secondary.opacity(0.2))
      .frame(width: 34, height: 34)
      .overlay(
        Text(String(comment.username.prefix(1)).uppercased())
          .font(.headline)
          .foregroundStyle(.secondary)
      )
  }
  
  // MARK: - Comment Content
  private var commentContent: some View {
    VStack(alignment: .leading, spacing: 4) {
      headerRow
      commentText
    }
  }
  
  // MARK: - Header Row
  private var headerRow: some View {
    HStack {
      Text(comment.username)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
      
      Spacer()
      
      optionsMenu
      
      Text(comment.createdAt, style: .time)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
  
  // MARK: - Comment Text
  private var commentText: some View {
    Text(comment.text)
      .font(.body)
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
  }
  
  // MARK: - Options Menu
  private var optionsMenu: some View {
    Menu {
      if comment.userID == auth.userID {
        Button(role: .destructive) {
          showAlert = true
        } label: {
          Label("Delete Comment", systemImage: "trash")
        }
      } else {
        Button(role: .destructive) {
          showAlert = true
        } label: {
          Label("Block User", systemImage: "hand.raised.fill")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .foregroundStyle(.secondary)
        .padding(6)
    }
    .alert(alertTitle, isPresented: $showAlert) {
      Button("Cancel", role: .cancel) {}
      Button(confirmButtonTitle, role: .destructive) {
        if comment.userID == auth.userID {
          deleteComment()
        } else {
          blockUser()
        }
      }
    } message: {
      Text(alertMessage)
    }
  }
}

// MARK: - Logic
private extension CommentRow {
  
  // MARK: - Actions
  func blockUser() {
    Task { @MainActor in
      guard !comment.userID.isEmpty else { return }
      isBlocking = true
      dataManager.addBlockedUser(comment.userID)
      isBlocking = false
      onBlocked(comment.userID)                  // ✅ notify parent
      print("🚫 Blocked userID: \(comment.userID)")
    }
  }
  
  func deleteComment() {
    Task {
      do {
        try await MemoryService.deleteComment(
          memoryID: memoryID,
          commentID: comment.id
        )
        await MainActor.run {
          onDeleted(comment.id)                  // ✅ notify parent
        }
      } catch {
        print("❌ Failed to delete comment: \(error.localizedDescription)")
      }
    }
  }
}

// MARK: - Alerts
private extension CommentRow {
  var alertTitle: String {
    comment.userID == auth.userID
    ? "Delete Comment?"
    : "Block \(comment.username)?"
  }
  
  var confirmButtonTitle: String {
    comment.userID == auth.userID ? "Delete" : "Block"
  }
  
  var alertMessage: String {
    comment.userID == auth.userID
    ? "This comment will be permanently deleted."
    : "This user’s comments will be hidden from your feed."
  }
}
