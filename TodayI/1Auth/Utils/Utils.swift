//
//  Utils.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 12/29/25.
//

import SwiftUI
import CryptoKit

// MARK: - Input style modifier
struct AuthInputStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding()
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

extension View {
  func authInputStyle() -> some View {
    self.modifier(AuthInputStyle())
  }
}

extension AuthView {
  
  // MARK: - Nonce helpers (unchanged)
  func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length
    
    while remaining > 0 {
      var randoms = [UInt8](repeating: 0, count: 16)
      let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
      if status != errSecSuccess { fatalError("Unable to generate nonce.") }
      randoms.forEach { rand in
        if remaining == 0 { return }
        if rand < charset.count {
          result.append(charset[Int(rand)])
          remaining -= 1
        }
      }
    }
    return result
  }
  
  func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.compactMap { String(format: "%02x", $0) }.joined()
  }
}

