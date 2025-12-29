import LocalAuthentication

enum BiometricAuthError: LocalizedError {
  case unavailable
  case failed(String)
  
  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "Face ID is not available on this device."
    case .failed(let message):
      return message
    }
  }
}

struct BiometricAuth {
  /// Prompts Face ID (and will fall back to device passcode if Face ID is locked out / not available).
  static func authenticate(reason: String) async throws {
    let context = LAContext()
    context.localizedFallbackTitle = "Use Passcode"
    
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      throw BiometricAuthError.unavailable
    }
    
    do {
      let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
      if !ok { throw BiometricAuthError.failed("Authentication was cancelled.") }
    } catch {
      // Convert the system error to something user-friendly
      if let laError = error as? LAError {
        throw BiometricAuthError.failed(laError.localizedDescription)
      }
      throw BiometricAuthError.failed(error.localizedDescription)
    }
  }
}
