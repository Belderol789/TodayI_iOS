import SwiftUI

struct AuthRequiredView: View {
  var action: (() -> Void)? = nil
  
  @Environment(\.colorScheme) private var scheme
  private let gradient = LinearGradient(
    colors: [
      .yellow, .orange, .pink, .green, .purple, .blue
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
  
  var body: some View {
    VStack(spacing: 24) {
      // MARK: - Icon / Illustration
      ZStack {
        Circle()
          .fill(gradient.opacity(0.2))
          .frame(width: 120, height: 120)
          .overlay(
            Image(systemName: "person.crop.circle.badge.plus")
              .font(.system(size: 56, weight: .semibold))
              .foregroundStyle(gradient)
          )
      }
      .shadow(radius: 6, y: 4)
      
      // MARK: - Text
      VStack(spacing: 6) {
        Text("Sign In Required")
          .font(.title2.bold())
        
        Text("You need to sign up or sign in to access this feature.")
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
          .padding(.horizontal)
      }
      
      // MARK: - Action Button
      Button {
        action?()
      } label: {
        Text("Sign Up / Sign In")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding()
          .background(gradient)
          .foregroundStyle(.white)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .shadow(color: .black.opacity(0.15), radius: 4, y: 3)
      }
      .padding(.horizontal, 40)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      Color(.systemBackground)
        .ignoresSafeArea()
    )
  }
}

#Preview {
  AuthRequiredView()
}
