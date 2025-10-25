//
//  AuthStore_Session.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 10/25/25.
//

import Foundation
import FirebaseAuth

extension AuthStore {
  // MARK: - Entry point
  func ensureSignedIn() async {
    // If already a registered user, do nothing
    if let u = Auth.auth().currentUser, !u.isAnonymous { return }
    
    if let u = Auth.auth().currentUser {
      await loadOrCreateProfile(for: u)
    } else {
      do {
        let result = try await Auth.auth().signInAnonymously()
        await loadOrCreateProfile(for: result.user)
      } catch {
        print("Anonymous sign-in failed:", error)
      }
    }
  }
  
  func startListening() {
    authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
      guard let self else { return }
      print("Auth changed. user: \(user?.uid ?? "none"), providers:", user?.providerData.map { $0.providerID } ?? [])
      
      Task { @MainActor in
        if let user {
          await self.loadOrCreateProfile(for: user)
        } else {
          // Only create anon user when we *know* no session is present
          do {
            let result = try await Auth.auth().signInAnonymously()
            await self.loadOrCreateProfile(for: result.user)
          } catch {
            print("Anonymous sign-in failed:", error)
          }
        }
      }
    }
  }
  
  func signOutToGuest() async {
    do {
      try Auth.auth().signOut()
    } catch {
      print("Sign out failed:", error)
    }
    await ensureSignedIn() // creates a fresh anonymous user
  }
}
