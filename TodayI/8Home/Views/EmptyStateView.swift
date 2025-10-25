import SwiftUI

struct EmptyStateView: View {
  let message: String
  let date: Date
  let buttonTitle: String
  let onButtonTap: () -> Void
  
  var body: some View {
    VStack(spacing: 12) {
      Text(message)
        .font(.headline)
        .multilineTextAlignment(.center)
      Text(formattedDate)
        .font(.subheadline)
        .foregroundColor(.secondary)
        .padding(.horizontal)
      Button(action: onButtonTap) {
        Text(buttonTitle)
          .font(.body.weight(.semibold))
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Capsule().fill(Color.accentColor.opacity(0.15)))
      }
    }
    .padding(.top, 80)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private extension EmptyStateView {
  var formattedDate: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
  }
}
