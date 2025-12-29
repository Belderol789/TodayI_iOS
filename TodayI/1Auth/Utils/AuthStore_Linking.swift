//
//  AuthStore_Linking.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/25/25.
//

import FirebaseAuth

extension AuthStore {

  // MARK: - Credential linking (keeps same uid)
  // Email/Password example:
  
  func linkEmailPassword(email: String, password: String) async throws {
    guard let user = Auth.auth().currentUser else {
      throw NSError(domain: "AuthStore", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No active session. Please try again."])
    }
    let cred = EmailAuthProvider.credential(withEmail: email, password: password)
    let result = try await user.link(with: cred)
    await loadOrCreateProfile(for: result.user)
  }
  
  func upgradeWithEmailPassword(_ email: String, password: String) async throws {
    try await linkEmailPassword(email: email, password: password)
  }
  
  @MainActor
  func signInOrLinkWithApple(_ credential: OAuthCredential) async {
    // If current user is anonymous, try to link first (keeps UID if truly new)
    if let current = Auth.auth().currentUser, current.isAnonymous {
      do {
        let result = try await current.link(with: credential)
        await loadOrCreateProfile(for: result.user)
        return
      } catch {
        let nsError = error as NSError
        // Correct way to read the auth error code
        if let errCode = AuthErrorCode(rawValue: nsError.code) {
          switch errCode {
          case .credentialAlreadyInUse, .accountExistsWithDifferentCredential:
            // Prefer the updated credential if Firebase provides one
            let updated = nsError.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential
            do {
              let signInResult: AuthDataResult
              if let updated {
                signInResult = try await Auth.auth().signIn(with: updated)
              } else {
                signInResult = try await Auth.auth().signIn(with: credential)
              }
              await loadOrCreateProfile(for: signInResult.user)
              // Best-effort cleanup of the temporary anonymous account
              try? await current.delete()
              return
            } catch {
              print("Apple sign-in after link-fallback failed:", error)
              return
            }
            
          default:
            print("Apple link failed with code \(errCode):", nsError)
            return
          }
        } else {
          print("Apple link failed (unknown code):", nsError)
          return
        }
      }
    }
    
    // Not anonymous (or no user yet): sign in directly
    do {
      let result = try await Auth.auth().signIn(with: credential)
      await loadOrCreateProfile(for: result.user)
    } catch {
      let nsError = error as NSError
      if let errCode = AuthErrorCode(rawValue: nsError.code) {
        print("Apple sign-in failed with code \(errCode):", nsError)
      } else {
        print("Apple sign-in failed:", nsError)
      }
    }
  }

  
}
