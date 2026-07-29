import Foundation
@_spi(Testing) import PeriscopeCore
import Testing

/// Opens the committed pre-upgrade store — written by the schema before
/// ambient snapshots, session attributes, and the relaunch-policy column
/// existed (`Fixtures/PreAmbientSchema.store`, produced by an `origin/main`
/// build) — so the lightweight migration the upgrade relies on is exercised
/// against a real old database instead of assumed.
///
/// Regenerating the fixture only takes a worktree of the pre-upgrade
/// revision, a scratch executable that opens `PeriscopeStore.onDisk` and
/// writes the rows asserted below, and a `PRAGMA wal_checkpoint(TRUNCATE)`
/// so the single file is self-contained.
struct PeriscopeSchemaUpgradeTests {
    /// The identities the fixture generator wrote.
    private static let oldSessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let orphanSpan =
        SpanID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
    private static let closedSpan =
        SpanID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)

    /// Copy the fixture into a scratch directory and open it with the
    /// *current* schema, starting a new attributed session — exactly what
    /// an app upgrade does on its first launch.
    private func openUpgradedStore() async throws -> PeriscopeStore {
        let fixture = try #require(
            Bundle.module.url(forResource: "PreAmbientSchema", withExtension: "store"),
        )
        let directory = URL.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true,
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("Periscope.store")
        try FileManager.default.copyItem(at: fixture, to: databaseURL)
        return try await PeriscopeStore.onDisk(
            databaseURL: databaseURL,
            session: .fixture(attributes: [.optimizationLevel: "-Onone"]),
        )
    }

    @Test func preUpgradeRowsSurviveTheMigration() async throws {
        let store = try await openUpgradedStore()

        let events = try await store.events(matching: LogQuery())
        // The five fixture rows plus the synthetic orphaned end this open's
        // sweep writes for the span the old launch left open.
        #expect(events.count == 6)
        let message = try #require(events.first { $0.message == "pre-upgrade message" })
        #expect(message.sessionID == Self.oldSessionID)
        #expect(message.ambientSnapshotID == nil)

        let closed = try await store.events(inSpan: Self.closedSpan)
        #expect(closed.count == 2)
    }

    /// The old session predates the attributes column; it must read back as
    /// "this build couldn't name itself", not fail or borrow the new
    /// session's attributes.
    @Test func preUpgradeSessionsReadBackWithoutAttributes() async throws {
        let store = try await openUpgradedStore()

        let sessions = try await store.sessions()
        let old = try #require(sessions.first { $0.id == Self.oldSessionID })
        #expect(old.attributes.isEmpty)
        #expect(old.appVersion == "0.9")

        let current = try #require(await store.currentSession)
        #expect(current.attributes[.optimizationLevel] == "-Onone")
    }

    /// The span the old launch left open has no relaunch-policy column, so
    /// the sweep must fall back to its payload — and attribute the
    /// synthetic end to the old session, not the upgrading one.
    @Test func theSweepClosesAPreUpgradeOpenSpanFromItsPayload() async throws {
        let store = try await openUpgradedStore()

        let pair = try await store.events(inSpan: Self.orphanSpan)
        #expect(pair.count == 2)
        let end = try #require(pair.first { $0.eventName == SpanEnded.eventName })
        #expect(end.spanExitMode == .orphaned)
        #expect(end.sessionID == Self.oldSessionID)
        #expect(try end.decode(SpanEnded.self).name == "old-open-work")
    }

    /// The fixture's ambient row was written as v1 (no `reporting` key);
    /// it must decode under the current shape.
    @Test func v1AmbientRowsDecodeAfterTheUpgrade() async throws {
        let store = try await openUpgradedStore()

        let events = try await store.events(matching: LogQuery())
        let row = try #require(events.first { $0.eventName == AmbientEvent.eventName })
        let decoded = try row.decode(AmbientEvent.self)
        #expect(decoded.kind == .network)
        #expect(decoded.reporting == .state)
        #expect(row.ambientSnapshotID == nil)
    }

    /// The upgraded store accepts writes that exercise the new columns and
    /// the new snapshot table.
    @Test func newWritesExerciseTheUpgradedSchema() async throws {
        let store = try await openUpgradedStore()

        let snapshot = AmbientSnapshot(id: UUID(), values: [.network: "satisfied"])
        let record = LogRecord(
            date: Date(),
            event: Message(level: .info, "post-upgrade"),
            scopes: [],
        ).stamped(ambient: snapshot)
        await store.write([record])

        #expect(await store.writeFailureCount == 0)
        let events = try await store.events(matching: LogQuery())
        let written = try #require(events.first { $0.message == "post-upgrade" })
        #expect(written.ambientSnapshotID == snapshot.id)
        #expect(try await store.ambientSnapshot(for: snapshot.id) == snapshot)
    }
}
