import SwiftData

/// Version 1 of the Where persistent schema — the original three models.
///
/// Formalizing the live schema as a `VersionedSchema` (rather than an ad-hoc
/// `Schema([...])`) lets `WhereMigrationPlan` evolve it deliberately: a future
/// `WhereSchemaV2` plus a migration stage replaces today's reliance on
/// implicit lightweight migration, and gives the launch flow a real version to
/// compare against (see `SchemaVersionMarker`).
enum WhereSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [SDLocationSample.self, SDEvidence.self, SDManualDay.self]
    }
}

/// The current schema version the app builds against. Bump this alias (and add
/// a migration stage to `WhereMigrationPlan`) when introducing a `WhereSchemaV2`.
typealias WhereCurrentSchema = WhereSchemaV1

/// Migration plan for the Where store.
///
/// V1 is the only version today, so there are no stages and opening an existing
/// store is a no-op. When a `WhereSchemaV2` lands, add it to `schemas` and append
/// a `.lightweight` or `.custom` stage here — the `.custom` form (with
/// `willMigrate`/`didMigrate`) is exercised end-to-end in the WhereCore tests.
enum WhereMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WhereSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
