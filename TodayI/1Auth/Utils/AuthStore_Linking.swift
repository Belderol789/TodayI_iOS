//
//  AuthStore_Linking.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/25/25.
//

import FirebaseAuth
import GoogleSignIn

extension AuthStore {

  // MARK: - Credential linking (keeps same uid)
  //
  // Apple and Google only. The email/password path was removed with its UI: a third
  // sign-in method to maintain (passwords, resets, typo'd addresses) for accounts that
  // exist mainly to post publicly and to carry a Premium backup.

  @MainActor
  func signInOrLinkWithGoogle(presenting viewController: UIViewController) async throws {
    guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
          let plist = NSDictionary(contentsOfFile: path),
          let clientID = plist["CLIENT_ID"] as? String else {
      throw NSError(domain: "AuthStore", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Missing Google client ID in GoogleService-Info.plist."])
    }

    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
    guard let idToken = result.user.idToken?.tokenString else {
      throw NSError(domain: "AuthStore", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Google sign-in failed: missing ID token."])
    }

    let credential = GoogleAuthProvider.credential(
      withIDToken: idToken,
      accessToken: result.user.accessToken.tokenString
    )

    if let current = Auth.auth().currentUser, current.isAnonymous {
      do {
        let linked = try await current.link(with: credential)
        await loadOrCreateProfile(for: linked.user)
        return
      } catch {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code),
              code == .credentialAlreadyInUse || code == .accountExistsWithDifferentCredential else {
          throw error
        }
        let updated = nsError.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential
        let signInResult = try await Auth.auth().signIn(with: updated ?? credential)
        await loadOrCreateProfile(for: signInResult.user)
        try? await current.delete()
        return
      }
    }

    let signInResult = try await Auth.auth().signIn(with: credential)
    await loadOrCreateProfile(for: signInResult.user)
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
