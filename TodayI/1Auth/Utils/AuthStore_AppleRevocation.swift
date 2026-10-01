import AuthenticationServices
import FirebaseAuth
import UIKit

extension AuthStore {

  // MARK: - Sign in with Apple token revocation

  /// Whether the signed-in account is linked to Sign in with Apple.
  var isLinkedToApple: Bool {
    Auth.auth().currentUser?.providerData.contains { $0.providerID == "apple.com" } ?? false
  }

  /// Revokes the account's Sign in with Apple tokens, as App Review guideline 5.1.1(v)
  /// requires for account deletion. Deleting the Firebase user alone leaves TodayI listed
  /// under the person's Apple ID → "Sign in with Apple" with its tokens still valid.
  ///
  /// Revocation needs a *fresh* authorization code — Apple's codes expire after five
  /// minutes and the one from the original sign-in is long gone — so this shows the Apple
  /// sheet once more. It must run **before** `deleteAccountData`: Firebase's revoke
  /// endpoint is authenticated as the current user, who no longer exists afterwards.
  ///
  /// Cancelling the sheet throws `DeleteError.cancelled`, which stops the deletion:
  /// backing out of a confirmation is a "no". Any other failure is logged and swallowed —
  /// refusing to delete someone's data over a revocation hiccup would be the worse outcome,
  /// and they can still remove TodayI from their Apple ID settings themselves.
  func revokeAppleTokenIfNeeded() async throws {
    guard isLinkedToApple else { return }

    let code: String
    do {
      code = try await AppleReauthenticator().authorizationCode()
    } catch let error as ASAuthorizationError where error.code == .canceled {
      print("🍎 Apple re-confirmation cancelled — account deletion stopped")
      throw DeleteError.cancelled
    } catch {
      print("❌ Apple re-confirmation failed, deleting without revocation:", error)
      return
    }

    do {
      try await Auth.auth().revokeToken(withAuthorizationCode: code)
      print("✅ Sign in with Apple token revoked")
    } catch {
      print("❌ Sign in with Apple token revocation failed:", error)
    }
  }
}

// MARK: - Apple re-authentication

/// Runs one Sign in with Apple request and hands back its authorization code.
///
/// No scopes are requested: the code is all revocation needs, and asking for name or
/// email again would show a consent screen for something we're about to delete.
@MainActor
private final class AppleReauthenticator: NSObject,
                                          ASAuthorizationControllerDelegate,
                                          ASAuthorizationControllerPresentationContextProviding {
  private var continuation: CheckedContinuation<String, Error>?

  func authorizationCode() async throws -> String {
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = []

    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.presentationContextProvider = self

    // The controller holds its delegate weakly; awaiting here keeps `self` alive until
    // one of the callbacks resumes.
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      controller.performRequests()
    }
  }

  nonisolated func authorizationController(controller: ASAuthorizationController,
                                           didCompleteWithAuthorization authorization: ASAuthorization) {
    let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?
      .authorizationCode
      .flatMap { String(data: $0, encoding: .utf8) }
    MainActor.assumeIsolated {
      if let code {
        continuation?.resume(returning: code)
      } else {
        continuation?.resume(throwing: ASAuthorizationError(.invalidResponse))
      }
      continuation = nil
    }
  }

  nonisolated func authorizationController(controller: ASAuthorizationController,
                                           didCompleteWithError error: Error) {
    MainActor.assumeIsolated {
      continuation?.resume(throwing: error)
      continuation = nil
    }
  }

  nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
  }
}
