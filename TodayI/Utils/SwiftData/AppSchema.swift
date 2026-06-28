import SwiftData

// MARK: - V1  (initial release schema)
// Contains: UserModel, MemoryModel, DateModel, BlockedUserList
// Fields added since dev start are all optional, so no lightweight migration
// is needed from previous simulator builds — SQLite adds the columns silently.
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
