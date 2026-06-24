import SwiftUI

struct AuthRequiredView: View {
  var action: (() -> Void)? = nil

  private var moodColors: [Color] { Mood.allCases.map(\.adaptiveColor) }

  private var moodGradient: LinearGradient {
    LinearGradient(colors: moodColors, startPoint: .leading, endPoint: .trailing)
  }

  var body: some View {
    VStack(spacing: 24) {
      HStack(spacing: 7) {
        ForEach(Mood.allCases) { mood in
          Circle()
            .fill(mood.adaptiveColor)
            .frame(width: 10, height: 10)
        }
      }
      .accessibilityHidden(true)

      VStack(spacing: 6) {
        Text("Sign in to continue")
          .font(.title3.bold())
          .accessibilityAddTraits(.isHeader)

        Text("Create an account or log in to use this feature.")
          .font(.subheadline)
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
          .padding(.horizontal)
      }

      Button {
        action?()
      } label: {
        Text("Sign up or log in")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .foregroundStyle(.white)
          .background(moodGradient)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .padding(.horizontal, 32)
      .accessibilityLabel("Sign up or log in")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground).ignoresSafeArea())
  }
}

#Preview {
  AuthRequiredView()
}
