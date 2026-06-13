import Foundation

/// Runs `operation` and cancels it if it hasn't finished within `seconds`.
/// Safe to call from any actor — the cancellation races the operation cleanly.
func withTimeout<T: Sendable>(
  seconds: Double,
  operation: @escaping @Sendable () async -> T?
) async -> T? {
  await withTaskGroup(of: T?.self) { group in
    group.addTask { await operation() }
    group.addTask {
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      return nil
    }
    // Return whichever finishes first, then cancel the other
    let result = await group.next() ?? nil
    group.cancelAll()
    return result
  }
}
