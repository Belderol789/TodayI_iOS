import SwiftData
import Foundation

@MainActor
final class SwiftDataManager {
  let context: ModelContext
  let store: EntitlementStore   // check free vs premium
  
  init(context: ModelContext, store: EntitlementStore) {
    self.context = context
    self.store = store
  }
}
