import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

struct AuthView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var scheme
  @EnvironmentObject private var auth: AuthStore

  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var currentNonce: String?

  private let privacyURL = URL(string: "https://kuzostudiosph.github.io/TodayI/privacy.html")!
  private let appleTermsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!



  var body: some View {
    VStack(spacing: 0) {
      dragHandle
      dismissButton

      ScrollView {
        VStack(spacing: 0) {
          appMark
            .padding(.bottom, 28)

          appleSignInButton
            .padding(.bottom, 10)

          googleSignInButton
            .padding(.bottom, 20)

          // Apple and Google only. Email/password was removed: it was a third sign-in
          // path to maintain (passwords, resets, typos in addresses) for an app whose
          // accounts exist mainly to post publicly and to carry a Premium backup.
          if let msg = errorMessage {
            errorBanner(msg)
              .padding(.bottom, 16)
          }

          legalFooter
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
      }
    }
    .background(Color(.systemBackground).ignoresSafeArea())
    .onChange(of: auth.isRegisteredUser) { _, isRegistered in
      if isRegistered { dismiss() }
    }
  }

  // MARK: - Subviews

  private var dragHandle: some View {
    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
      .fill(Color(.tertiaryLabel))
      .frame(width: 36, height: 5)
      .padding(.top, 10)
      .accessibilityHidden(true)
  }

  private var dismissButton: some View {
    HStack {
      Spacer()
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
          .background(Color(.secondarySystemBackground))
          .clipShape(Circle())
      }
      .accessibilityLabel("Close")
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 4)
  }

  private var appMark: some View {
    VStack(spacing: 10) {
      HStack(spacing: 7) {
        ForEach(Mood.allCases) { mood in
          Circle()
            .fill(mood.adaptiveColor)
            .frame(width: 11, height: 11)
        }
      }
      .accessibilityHidden(true)

      Text("TodayI")
        .font(.title.bold())
        .accessibilityAddTraits(.isHeader)

      Text("Your day, remembered.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .multilineTextAlignment(.center)
  }

  private var googleSignInButton: some View {
    Button {
      Task { await handleGoogleSignIn() }
    } label: {
      HStack(spacing: 10) {
        Image("google_logo")
          .resizable()
          .scaledToFit()
          .frame(width: 18, height: 18)
        Text("Continue with Google")
          .font(.system(size: 17, weight: .semibold))
      }
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .foregroundStyle(Color(.label))
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Color(.separator), lineWidth: 0.5)
      )
      .opacity(isLoading ? 0.6 : 1)
    }
    .disabled(isLoading)
    .accessibilityLabel("Continue with Google")
  }

  private var appleSignInButton: some View {
    ZStack {
      SignInWithAppleButton(onRequest: configureAppleRequest, onCompletion: handleAppleCompletion)
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .allowsHitTesting(!isLoading)
        .opacity(isLoading ? 0.6 : 1)

      if isLoading {
        ProgressView()
          .accessibilityLabel("Signing in")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Continue with Apple")
    .accessibilityHint("Signs in with your Apple ID.")
  }

  private func errorBanner(_ msg: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.footnote)
        .accessibilityHidden(true)
      Text(msg)
        .font(.footnote)
      Spacer()
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .transition(.opacity.combined(with: .move(edge: .top)))
    .accessibilityLabel("Error. \(msg)")
  }

  private var legalFooter: some View {
    HStack(spacing: 20) {
      Link("Privacy Policy", destination: privacyURL)
      Link("Terms of Service", destination: appleTermsURL)
    }
    .font(.caption)
    .foregroundStyle(.tertiary)
    .padding(.top, 12)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Color(.separator))
        .frame(height: 0.5)
    }
  }
}

// MARK: - Google Sign In
private extension AuthView {
  func handleGoogleSignIn() async {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first?.rootViewController else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      try await auth.signInOrLinkWithGoogle(presenting: root)
    } catch {
      withAnimation { errorMessage = friendlyMessage(for: error) }
    }
  }
}

// MARK: - Error copy
private extension AuthView {
  func friendlyMessage(for error: Error) -> String {
    let ns = error as NSError
    guard let code = AuthErrorCode(rawValue: ns.code) else { return error.localizedDescription }
    switch code {
    case .credentialAlreadyInUse, .emailAlreadyInUse:
      return "That account is already linked to another TodayI profile."
    case .networkError: return "Check your connection and try again."
    default: return error.localizedDescription
    }
  }
}

// MARK: - Apple Sign In
private extension AuthView {
  func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
    // No `.fullName`: the given name used to become the public username, so the first
    // Global post put someone's real name in front of strangers without asking. People
    // keep their guest-XXXX name until they choose one in Settings.
    request.requestedScopes = [.email]
    let nonce = randomNonceString()
    currentNonce = nonce
    request.nonce = sha256(nonce)
  }

  func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
    switch result {
    case .failure(let err):
      withAnimation { errorMessage = err.localizedDescription }

    case .success(let authResult):
      guard
        let appleIDCredential = authResult.credential as? ASAuthorizationAppleIDCredential,
        let tokenData = appleIDCredential.identityToken,
        let idTokenString = String(data: tokenData, encoding: .utf8),
        let rawNonce = currentNonce
      else {
        withAnimation { errorMessage = "Apple sign-in failed. Please try again." }
        return
      }

      let credential = OAuthProvider.credential(
        providerID: .apple,
        idToken: idTokenString,
        rawNonce: rawNonce
      )

      let suggestedEmail = appleIDCredential.email

      Task {
        isLoading = true
        defer { Task { @MainActor in isLoading = false; currentNonce = nil } }

        await auth.signInOrLinkWithApple(credential)

        if let e = suggestedEmail, let uid = auth.userID {
          try? await Firestore.firestore().collection("users").document(uid)
            .updateData(["email": e, "updatedAt": FieldValue.serverTimestamp()])
        }
      }
    }
  }
}
