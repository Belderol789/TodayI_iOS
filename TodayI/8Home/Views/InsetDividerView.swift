import SwiftUI

struct InsetDivider: View {
  var horizontalPadding: CGFloat = 16
  var height: CGFloat = 1
  var color: Color = .secondary.opacity(0.3) // works well in light/dark
  
  var body: some View {
    Rectangle()
      .fill(color)
      .frame(height: height)
      .padding(.horizontal, horizontalPadding)
  }
}
