import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

struct AuthView: View {
  enum Mode { case signup, login }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var scheme
  @EnvironmentObject private var auth: AuthStore

  @State private var mode: Mode = .signup
  @State private var email = ""
  @State private var password = ""
  @State private var revealPassword = false
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var currentNonce: String?

  private let privacyURL = URL(string: "https://github.com/KuzoStudiosPH/TodayI/wiki/Privacy-Policy")!
  private let appleTermsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

  private var emailLooksValid: Bool { email.contains("@") && email.contains(".") && email.count > 5 }
  private var passwordLooksValid: Bool { password.count >= 6 }
  private var canSubmit: Bool { emailLooksValid && passwordLooksValid && !isLoading }

  private var moodColors: [Color] { Mood.allCases.map(\.adaptiveColor) }

  private var moodGradient: LinearGradient {
    LinearGradient(colors: moodColors, startPoint: .leading, endPoint: .trailing)
  }

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

          emailDivider
            .padding(.bottom, 16)

          emailFields
            .padding(.bottom, 8)

          submitButton
            .padding(.bottom, 16)

          modeToggle
            .padding(.bottom, 20)

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

  private var emailDivider: some View {
    HStack(spacing: 12) {
      Rectangle().fill(Color(.separator)).frame(height: 0.5)
      Text("or continue with email")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .fixedSize()
      Rectangle().fill(Color(.separator)).frame(height: 0.5)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Or continue with email")
  }

  private var emailFields: some View {
    VStack(spacing: 10) {
      if let msg = errorMessage {
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

      TextField("Email", text: $email)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textContentType(.emailAddress)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color(.separator), lineWidth: 0.5)
        )
        .disabled(isLoading)
        .accessibilityLabel("Email")

      HStack {
        Group {
          if revealPassword {
            TextField("Password", text: $password)
          } else {
            SecureField("Password", text: $password)
          }
        }
        .textContentType(mode == .signup ? .newPassword : .password)
        .disabled(isLoading)
        .accessibilityLabel("Password")
        .accessibilityHint("Minimum 6 characters.")

        Button {
          revealPassword.toggle()
        } label: {
          Image(systemName: revealPassword ? "eye.slash" : "eye")
            .foregroundStyle(.secondary)
            .font(.system(size: 15))
        }
        .disabled(isLoading)
        .accessibilityLabel(revealPassword ? "Hide password" : "Show password")
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 13)
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color(.separator), lineWidth: 0.5)
      )
    }
  }

  private var submitButton: some View {
    Button {
      Task { await handleEmailPrimary() }
    } label: {
      HStack(spacing: 8) {
        if isLoading { ProgressView().tint(.white) }
        Text(mode == .signup ? "Create account" : "Log in")
          .font(.headline)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .foregroundStyle(.white)
      .background(
        canSubmit
          ? AnyShapeStyle(moodGradient)
          : AnyShapeStyle(Color(.tertiaryLabel))
      )
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .disabled(!canSubmit)
    .animation(.easeInOut(duration: 0.2), value: canSubmit)
    .accessibilityLabel(mode == .signup ? "Create account" : "Log in")
    .accessibilityHint(isLoading ? "Please wait." : "Submits your email and password.")
  }

  private var modeToggle: some View {
    Button {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        mode = (mode == .signup ? .login : .signup)
        errorMessage = nil
      }
    } label: {
      Group {
        if mode == .signup {
          Text("Already have an account? \(Text("Log in").bold())")
        } else {
          Text("No account? \(Text("Sign up").bold())")
        }
      }
      .font(.subheadline)
      .foregroundStyle(moodColors.last ?? .purple)
    }
    .disabled(isLoading)
    .accessibilityHint("Switches between sign up and log in.")
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

// MARK: - Email flow
private extension AuthView {
  func handleEmailPrimary() async {
    guard emailLooksValid && passwordLooksValid else {
      withAnimation { errorMessage = "Please enter a valid email and a password with at least 6 characters." }
      return
    }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      switch mode {
      case .signup:
        try await auth.upgradeWithEmailPassword(email, password: password)
      case .login:
        try await auth.signInOrLinkWithEmail(email, password: password)
      }
    } catch {
      let ns = error as NSError
      let code = AuthErrorCode(rawValue: ns.code)
      print("Email flow failed:", code as Any, ns)
      withAnimation { errorMessage = friendlyMessage(for: error) }
    }
  }

  func friendlyMessage(for error: Error) -> String {
    let ns = error as NSError
    guard let code = AuthErrorCode(rawValue: ns.code) else { return error.localizedDescription }
    switch code {
    case .wrongPassword, .invalidCredential: return "Incorrect email or password."
    case .userNotFound: return "No account found with that email."
    case .emailAlreadyInUse: return "That email is already in use. Try logging in instead."
    case .weakPassword: return "Password must be at least 6 characters."
    case .invalidEmail: return "Please enter a valid email address."
    case .networkError: return "Check your connection and try again."
    default: return error.localizedDescription
    }
  }
}

// MARK: - Apple Sign In
private extension AuthView {
  func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
    request.requestedScopes = [.fullName, .email]
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

      let suggestedName = appleIDCredential.fullName?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines)
      let suggestedEmail = appleIDCredential.email

      Task {
        isLoading = true
        defer { Task { @MainActor in isLoading = false; currentNonce = nil } }

        await auth.signInOrLinkWithApple(credential)

        if let name = suggestedName, !name.isEmpty {
          await auth.updateUsername(name)
        }
        if let e = suggestedEmail, let uid = auth.userID {
          try? await Firestore.firestore().collection("users").document(uid)
            .updateData(["email": e, "updatedAt": FieldValue.serverTimestamp()])
        }
      }
    }
  }
}
