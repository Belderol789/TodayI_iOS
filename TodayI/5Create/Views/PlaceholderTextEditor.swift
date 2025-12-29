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
          .font(.body)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 12)
          .padding(.vertical, 16)
          .allowsHitTesting(false) // <- let taps go to the editor
      }
      
      TextEditor(text: $text)
        .font(.body)                       // <- ensure consistent text metrics
        .scrollContentBackground(.hidden)  // <- hide UIKit bg
        .background(Color.clear)           // <- keep editor itself clear
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .textInputAutocapitalization(.sentences)
        .disableAutocorrection(false)
        .compositingGroup()                // <- nudge renderer to redraw
        .opacity(0.999)                    // <- tiny hack to avoid caching glitch
    }
    .frame(minHeight: minHeight, maxHeight: maxHeight)
    .onAppear {
      UITextView.appearance().textColor = UIColor.label
      UITextView.appearance().tintColor = UIColor.label
    }
    .background(                           // <- your rounded container bg
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(.secondarySystemBackground))
    )
  }
}
