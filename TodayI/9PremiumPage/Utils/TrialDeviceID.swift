import Security
import Foundation

enum TrialDeviceID {
  private static let service = "com.kuzostudiosph.TodayI"
  private static let account = "deviceTrialID"
  
  static func getOrCreate() -> String {
    if let existing = read() { return existing }
    let newID = UUID().uuidString
    save(newID)
    return newID
  }
  
  private static func read() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    
    var item: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data,
          let str = String(data: data, encoding: .utf8)
    else { return nil }
    
    return str
  }
  
  private static func save(_ value: String) {
    let data = Data(value.utf8)
    
    // Delete any existing first (simplest)
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(deleteQuery as CFDictionary)
    
    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    SecItemAdd(addQuery as CFDictionary, nil)
  }
}
