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
        // Set on the view, never through `UITextView.appearance()`. The appearance
        // proxy applies once, as a view enters a window, so the colour it resolved
        // at that moment stuck — text stayed dark in dark mode until a light/dark
        // round trip rebuilt the view. It was also global: it repainted every
        // UITextView in the app, not just this one.
        .foregroundStyle(.primary)
        .tint(.primary)                    // caret, was appearance().tintColor
        .scrollContentBackground(.hidden)  // <- hide UIKit bg
        .background(Color.clear)           // <- keep editor itself clear
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .textInputAutocapitalization(.sentences)
        .disableAutocorrection(false)
    }
    .frame(minHeight: minHeight, maxHeight: maxHeight)
    .background(                           // <- your rounded container bg
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(.secondarySystemBackground))
    )
  }
}
