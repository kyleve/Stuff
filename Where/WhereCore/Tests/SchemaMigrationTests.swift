import Foundation
import SwiftData
import Testing
import WhereCore

private func ephemeralDefaults() -> UserDefaults {
    let suite = "where.schema.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

struct SchemaVersionMarkerTests {
    @Test func freshMarkerExpectsNoMigration() {
        let marker = SchemaVersionMarker(
            defaults: ephemeralDefaults(),
            currentVersion: Schema.Version(1, 0, 0),
        )
        #expect(marker.recordedVersion == nil)
        #expect(!marker.migrationExpected)
    }

    @Test func recordingRoundTrips() {
        let marker = SchemaVersionMarker(
            defaults: ephemeralDefaults(),
            currentVersion: Schema.Version(2, 1, 0),
        )
        marker.recordCurrentVersion()
        #expect(marker.recordedVersion == Schema.Version(2, 1, 0))
        #expect(!marker.migrationExpected)
    }

    @Test func olderRecordedVersionExpectsMigration() {
        let defaults = ephemeralDefaults()
        // Simulate a prior launch on an older schema.
        SchemaVersionMarker(defaults: defaults, currentVersion: Schema.Version(0, 9, 0))
            .recordCurrentVersion()

        let current = SchemaVersionMarker(
            defaults: defaults,
            currentVersion: Schema.Version(1, 0, 0),
        )
        #expect(current.migrationExpected)
    }
}

struct StoreOpenTests {
    @Test func openFreshStoreReportsNoMigrationAndRecordsVersion() throws {
        let marker = SchemaVersionMarker(
            defaults: ephemeralDefaults(),
            currentVersion: Schema.Version(1, 0, 0),
        )
        let opened = try SwiftDataStore.open(storage: .inMemory, marker: marker)
        #expect(!opened.migrationWasExpected)
        #expect(marker.recordedVersion == Schema.Version(1, 0, 0))
    }

    @Test func openReportsMigrationWhenMarkerIsBehind() throws {
        let defaults = ephemeralDefaults()
        SchemaVersionMarker(defaults: defaults, currentVersion: Schema.Version(0, 9, 0))
            .recordCurrentVersion()

        let marker = SchemaVersionMarker(
            defaults: defaults,
            currentVersion: Schema.Version(1, 0, 0),
        )
        let opened = try SwiftDataStore.open(storage: .inMemory, marker: marker)
        #expect(opened.migrationWasExpected)
        #expect(marker.recordedVersion == Schema.Version(1, 0, 0))
    }
}

// MARK: - Custom migration stage (end-to-end)

/// Two throwaway schema versions and a custom stage, used to prove that a
/// `.custom` migration stage actually runs and transforms persisted data —
/// the mechanism `WhereMigrationPlan` will use when a real `WhereSchemaV2`
/// lands.
private enum MigrationDemoV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Item.self]
    }

    @Model final class Item {
        var name: String?
        init() {}
    }
}

private enum MigrationDemoV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Item.self]
    }

    @Model final class Item {
        var name: String?
        var didMigrate: Bool?
        init() {}
    }
}

private enum MigrationDemoPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MigrationDemoV1.self, MigrationDemoV2.self]
    }

    static var stages: [MigrationStage] {
        [.custom(
            fromVersion: MigrationDemoV1.self,
            toVersion: MigrationDemoV2.self,
            willMigrate: nil,
            didMigrate: { context in
                for item in try context.fetch(FetchDescriptor<MigrationDemoV2.Item>()) {
                    item.didMigrate = true
                }
                try context.save()
            },
        )]
    }
}

private struct MigratedItem {
    let name: String?
    let didMigrate: Bool?
}

struct CustomMigrationStageTests {
    @Test func customStageRunsAndBackfillsData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("demo.store")

        try Self.seedV1(at: url)
        let migrated = try Self.openV2(at: url)

        #expect(migrated.count == 1)
        #expect(migrated.first?.name == "alpha")
        // The new field was backfilled by the custom stage's didMigrate.
        #expect(migrated.first?.didMigrate == true)
    }

    /// Seeds a V1 store in its own scope so the container is released before
    /// the V2 container reopens the same file and migrates it.
    private static func seedV1(at url: URL) throws {
        let schema = Schema(versionedSchema: MigrationDemoV1.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url),
        )
        let context = ModelContext(container)
        let item = MigrationDemoV1.Item()
        item.name = "alpha"
        context.insert(item)
        try context.save()
    }

    private static func openV2(at url: URL) throws -> [MigratedItem] {
        let schema = Schema(versionedSchema: MigrationDemoV2.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: MigrationDemoPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url),
        )
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<MigrationDemoV2.Item>()).map {
            MigratedItem(name: $0.name, didMigrate: $0.didMigrate)
        }
    }
}
