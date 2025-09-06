//
//  Keychain.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/5/25.
//

import Foundation

enum KeychainError: Error { case unexpectedStatus(OSStatus) }

struct Keychain {
  static func save(service: String, account: String, data: Data) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    // Try update first
    let attrs: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    if status == errSecItemNotFound {
      var addQuery = query
      addQuery[kSecValueData as String] = data
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    } else if status != errSecSuccess {
      throw KeychainError.unexpectedStatus(status)
    }
  }
  
  static func load(service: String, account: String) throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    return item as? Data
  }
}
