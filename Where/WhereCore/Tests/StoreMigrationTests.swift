import Foundation
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers the reusable migration runner (`SwiftDataStore.runMigrations`): which
/// migrations run, in what order, and how the applied-version marker gates them.
struct StoreMigrationTests {
    private let calendar = WhereCoreTestSupport.calendar()

    /// Records the versions its stub migrations were asked to apply, in order.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var applied: [Int] = []
        func record(_ version: Int) {
            lock.withLock { applied.append(version) }
        }
    }

    private struct StubMigration: StoreMigration {
        let version: Int
        let name = "stub"
        let recorder: Recorder
        func migrate(_: ModelContext, calendar _: Calendar) throws {
            recorder.record(version)
        }
    }

    @Test func runsPendingMigrationsInAscendingOrderAndBumpsMarker() async throws {
        let store = try SwiftDataStore.inMemory()
        let versionStore = InMemoryKeyValueStore()
        let recorder = Recorder()

        try await store.runMigrations(
            [
                StubMigration(version: 2, recorder: recorder),
                StubMigration(version: 1, recorder: recorder),
            ],
            calendar: calendar,
            versionStore: versionStore,
        )

        #expect(recorder.applied == [1, 2])
        #expect(versionStore.object(forKey: SwiftDataStore.migrationVersionKey) as? Int == 2)
    }

    @Test func skipsMigrationsAtOrBelowTheAppliedMarker() async throws {
        let store = try SwiftDataStore.inMemory()
        let versionStore = InMemoryKeyValueStore()
        versionStore.set(1, forKey: SwiftDataStore.migrationVersionKey)
        let recorder = Recorder()

        try await store.runMigrations(
            [
                StubMigration(version: 1, recorder: recorder),
                StubMigration(version: 2, recorder: recorder),
            ],
            calendar: calendar,
            versionStore: versionStore,
        )

        #expect(recorder.applied == [2])
        #expect(versionStore.object(forKey: SwiftDataStore.migrationVersionKey) as? Int == 2)
    }

    @Test func isANoOpWhenEverythingIsAlreadyApplied() async throws {
        let store = try SwiftDataStore.inMemory()
        let versionStore = InMemoryKeyValueStore()
        versionStore.set(5, forKey: SwiftDataStore.migrationVersionKey)
        let recorder = Recorder()

        try await store.runMigrations(
            [
                StubMigration(version: 1, recorder: recorder),
                StubMigration(version: 5, recorder: recorder),
            ],
            calendar: calendar,
            versionStore: versionStore,
        )

        #expect(recorder.applied.isEmpty)
        #expect(versionStore.object(forKey: SwiftDataStore.migrationVersionKey) as? Int == 5)
    }
}
