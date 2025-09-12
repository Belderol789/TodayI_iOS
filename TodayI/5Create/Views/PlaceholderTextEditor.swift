import SwiftUI

struct PlaceholderTextEditor: View {
  @Binding var text: String
  var placeholder: String
  var minHeight: CGFloat = 160
  var maxHeight: CGFloat = 220
  
  var body: some View {
    ZStack(alignment: .topLeading) {
      if text.isEmpty {
        Text(placeholder)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 12)
          .padding(.vertical, 12)
      }
      
      TextEditor(text: $text)
        .textEditorStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 8)   // inner padding so text doesn’t sit on the edge
        .padding(.top, 8)          // avoids overlapping with placeholder
    }
    .frame(minHeight: minHeight, maxHeight: maxHeight)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(.secondarySystemBackground))
    )
  }
}
