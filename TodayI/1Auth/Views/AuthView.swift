import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

struct AuthView: View {
  enum Mode: String, CaseIterable { case signup = "Sign Up", login = "Log In" }
  
  @Environment(\.colorScheme) private var scheme
  @EnvironmentObject private var auth: AuthStore
  
  @State private var mode: Mode = .signup
  @State private var email = ""
  @State private var password = ""
  @State private var revealPassword = false
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var currentNonce: String?
  
  // Basic validation checks
  private var emailLooksValid: Bool { email.contains("@") && email.contains(".") && email.count > 5 }
  private var passwordLooksValid: Bool { password.count >= 6 }
  private var canSubmit: Bool {
    emailLooksValid && passwordLooksValid && !isLoading
  }
  
  var body: some View {
    ZStack {
      // Background gradient
      LinearGradient(
        colors: scheme == .dark
        ? [.black, Color(.systemGray6).opacity(0.06)]
        : [Color(.systemGray6), .white],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
      .ignoresSafeArea()
      
      VStack(spacing: 20) {
        VStack(spacing: 8) {
          Text("Welcome to TodayI")
            .font(.largeTitle.weight(.bold))
            .tracking(0.5)
          
          Text(mode == .signup ? "Create your account" : "Welcome back")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        
        // Picker for login / signup
        Picker("", selection: $mode) {
          ForEach(Mode.allCases, id: \.self) { m in
            Text(m.rawValue).tag(m)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        
        VStack(spacing: 16) {
          // Error message if any
          if let msg = errorMessage {
            HStack {
              Image(systemName: "exclamationmark.triangle.fill")
              Text(msg).font(.footnote)
              Spacer()
            }
            .foregroundStyle(.white)
            .padding(10)
            .background(Capsule().fill(.red.gradient))
            .transition(.opacity.combined(with: .move(edge: .top)))
          }
          
          // Email input
          TextField("Email", text: $email)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .authInputStyle()
          
          // Password input with eye icon toggle
          HStack {
            Group {
              if revealPassword {
                TextField("Password (min 6 chars)", text: $password)
              } else {
                SecureField("Password (min 6 chars)", text: $password)
              }
            }
            .textContentType(.password)
            
            Button {
              revealPassword.toggle()
            } label: {
              Image(systemName: revealPassword ? "eye.slash.fill" : "eye.fill")
                .foregroundColor(.secondary)
            }
          }
          .authInputStyle()
          
          Button {
            Task { await handleEmailPrimary() }
          } label: {
            HStack {
              if isLoading { ProgressView().padding(.trailing, 4) }
              Text(mode == .signup ? "Create account" : "Log in")
                .font(.headline)
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(!canSubmit)
          .opacity(canSubmit ? 1 : 0.6)
          
          Button {
            withAnimation(.spring) {
              mode = (mode == .signup ? .login : .signup)
              errorMessage = nil
            }
          } label: {
            Text(mode == .signup ? "Already have an account? Log in"
                 : "No account? Sign up")
            .font(.footnote.weight(.semibold))
          }
          .buttonStyle(.plain)
          
          HStack {
            Rectangle().fill(.secondary.opacity(0.2)).frame(height: 1)
            Text("or").foregroundStyle(.secondary).font(.caption)
            Rectangle().fill(.secondary.opacity(0.2)).frame(height: 1)
          }
          .padding(.vertical, 4)
          
          ZStack {
            SignInWithAppleButton(onRequest: configureAppleRequest,
                                  onCompletion: handleAppleCompletion)
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(!isLoading)
            .opacity(isLoading ? 0.7 : 1)
            
            if isLoading {
              ProgressView()
            }
          }
          
          Text("By continuing you agree to the Terms & Privacy Policy.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 6)
        }
        .padding(20)
        .background(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal)
        
        Spacer(minLength: 0)
      }
      .padding(.vertical)
    }
    .onAppear {
      mode = .signup
    }
  }
}

// MARK: - Email flows
private extension AuthView {
  func handleEmailPrimary() async {
    guard emailLooksValid && passwordLooksValid else {
      errorMessage = "Please enter a valid email and a password with at least 6 characters."
      return
    }
    await MainActor.run { isLoading = true; errorMessage = nil }
    do {
      switch mode {
      case .signup:
        try await auth.upgradeWithEmailPassword(email, password: password)
      case .login:
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
      }
    } catch {
      let ns = error as NSError
      let code = AuthErrorCode(rawValue: ns.code)
      print("Email flow failed:", code as Any, ns)
      await MainActor.run { errorMessage = error.localizedDescription }
    }
    await MainActor.run { isLoading = false }
  }
}

// MARK: - Apple Sign In (unchanged)
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
      errorMessage = err.localizedDescription
      
    case .success(let authResult):
      guard
        let appleIDCredential = authResult.credential as? ASAuthorizationAppleIDCredential,
        let tokenData = appleIDCredential.identityToken,
        let idTokenString = String(data: tokenData, encoding: .utf8),
        let rawNonce = currentNonce
      else {
        errorMessage = "Apple token/nonce missing."
        return
      }
      
      let credential = OAuthProvider.credential(
        providerID: .apple,
        idToken: idTokenString,
        rawNonce: rawNonce
      )
      
      // Optional suggested values (only present on first auth)
      let suggestedName = appleIDCredential.fullName?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines)
      let suggestedEmail = appleIDCredential.email
      
      Task {
        await MainActor.run { isLoading = true; errorMessage = nil }
        defer {
          Task { @MainActor in
            isLoading = false
            currentNonce = nil
          }
        }
        
        do {
          await auth.signInOrLinkWithApple(credential)
          
          // if you want to set a nicer username on first run:
          if let name = suggestedName, !name.isEmpty {
            await auth.updateUsername(name)
          }
          
          // If you want to persist the returned email into Firestore (optional):
          if let e = suggestedEmail, let uid = auth.userID {
            try await Firestore.firestore().collection("users").document(uid)
              .updateData(["email": e, "updatedAt": FieldValue.serverTimestamp()])
          }
        } catch {
          await MainActor.run { errorMessage = error.localizedDescription }
        }
      }
    }
  }
}

