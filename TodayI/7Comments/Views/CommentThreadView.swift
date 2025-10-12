import SwiftUI
import FirebaseFirestore

struct CommentThreadView: View {
  let memory: MemoryModel
  @StateObject private var vm: CommentThreadViewModel
  
  init(memory: MemoryModel) {
    self.memory = memory
    _vm = StateObject(wrappedValue: CommentThreadViewModel(memoryID: memory.id))
  }
  
  var body: some View {
    VStack(spacing: 0) {
      // 🧠 MemoryRow at the top
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 16) {
            // Show the post itself
            MemoryRow(memory: memory)
              .padding(.horizontal)
              .padding(.top, 8)
            
            Divider()
            
            // Comments Section
            if vm.isLoading {
              ProgressView("Loading comments…")
                .padding(.top, 40)
            } else if vm.comments.isEmpty {
              Text("No comments yet.")
                .foregroundStyle(.secondary)
                .padding(.top, 40)
            } else {
              ForEach(vm.comments) { comment in
                CommentRow(comment: comment)
                  .padding(.horizontal)
                  .padding(.vertical, 4)
              }
            }
          }
        }
      }
      
      Divider()
      
      // Input bar at the bottom
      commentBox
    }
    .navigationTitle("Comments")
    .navigationBarTitleDisplayMode(.inline)
    .task { await vm.loadComments() }
  }
  
  private var commentBox: some View {
    // MARK: - Comment Input Bar
    HStack(alignment: .center, spacing: 8) {
      // Expanding TextEditor
      ZStack(alignment: .topLeading) {
        if vm.newComment.isEmpty {
          Text("Add a comment…")
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .allowsHitTesting(false)
        }
        
        // TextEditor that grows with content
        TextEditor(text: $vm.newComment)
          .scrollContentBackground(.hidden)
          .background(.clear)
          .padding(.vertical, 8)
          .padding(.horizontal, 8)
          .frame(minHeight: 36, maxHeight: 120) // adjust as needed
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
