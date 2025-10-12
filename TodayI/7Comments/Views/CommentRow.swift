import SwiftUI

struct CommentRow: View {
  let comment: CommentDTO
  
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      // Optional: avatar placeholder
      Circle()
        .fill(Color.secondary.opacity(0.2))
        .frame(width: 34, height: 34)
        .overlay(
          Text(String(comment.username.prefix(1)).uppercased())
            .font(.headline)
            .foregroundStyle(.secondary)
        )
      
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(comment.username)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          
          Spacer()
          
          Text(comment.createdAt, style: .time)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        
        Text(comment.text)
          .font(.body)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 6)
  }
}
