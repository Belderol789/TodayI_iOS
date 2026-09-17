import SwiftData

// MARK: - V1  (initial release schema)
// Contains: UserModel, MemoryModel, DateModel, BlockedUserList
//
// Verified 2026-09-17 by building the pre-audio commit (dc74a61, before this file
// existed), generating a store from it, and opening that store with current HEAD:
// SwiftData lightweight-migrates added properties — optional, defaulted, AND plain
// non-optional (`likedBy: [String]` back-fills with no default) — and adopting a
// VersionedSchema over a store written without one is also fine. So a
// `loadIssueModelContainer` here is NOT a schema-evolution problem; look at disk
// space, file protection, or a corrupted store instead.
enum AppSchemaV1: VersionedSchema {
  static var versionIdentifier = Schema.Version(1, 0, 0)
  static var models: [any PersistentModel.Type] {
    [UserModel.self, MemoryModel.self, DateModel.self, BlockedUserList.self]
  }
}

// MARK: - Migration plan
// To add a new schema version:
//   1. Copy AppSchemaV1 as AppSchemaV2, bump versionIdentifier to (1, 1, 0).
//   2. Inside AppSchemaV2, redeclare only the models that changed (as typealiases
//      or nested @Model classes). Unchanged models can be typealiased from V1.
//   3. Add a MigrationStage below:
//        .lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self)
//      for property additions/removals, or .custom(...) for data transforms.
//   4. Append AppSchemaV2.self to the schemas array.
enum AppMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
  static var stages: [MigrationStage] { [] }
}
