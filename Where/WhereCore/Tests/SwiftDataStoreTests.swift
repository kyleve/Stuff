import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

/// `SwiftDataStore` behavior as a `WhereStore` — specifically the `changes()`
/// signal that backs the app's single read-refresh path. The fan-out itself is
/// covered by `StoreChangeBroadcasterTests`; here we assert the *store* fires it
/// on a committed `perform` and stays silent on a rolled-back one.
struct SwiftDataStoreTests {
    private static let calendar = WhereCoreTestSupport.calendar()

    private let day = DayPresence(
        date: Date(timeIntervalSince1970: 0),
        in: SwiftDataStoreTests.calendar,
        regions: [.california],
    )

    @Test func committedWritePingsChanges() async throws {
        let store = try SwiftDataStore.inMemory()
        // Subscribe before writing so the continuation exists when the commit
        // fires; the stream buffers the newest ping, so iterating after still
        // sees it.
        let stream = store.changes()

        try await store.perform { try await store.setManualDay(day) }

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    @Test func nestedPerformStillPingsOnCommit() async throws {
        let store = try SwiftDataStore.inMemory()
        let stream = store.changes()

        // A nested `perform` reuses the in-flight transaction; only the
        // outermost commit pings, so the consumer still gets its signal.
        try await store.perform {
            try await store.perform { try await store.setManualDay(day) }
        }

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    /// Two (or more) *outermost* `perform` calls issued from independent tasks
    /// must be serialized. Because `perform`'s block is `async` and the store is
    /// an `actor`, naive reentrancy once let a concurrent top-level `perform`
    /// observe the in-flight peer, take the nested-reuse branch, and then trap in
    /// `mutationContext()` when the real owner cleared the peer out from under it
    /// (the shipped crash). Every transaction must now run to completion one at a
    /// time, and every write must commit.
    @Test func concurrentOutermostPerformsSerializeAndAllCommit() async throws {
        let store = try SwiftDataStore.inMemory()
        let observer = ConcurrencyObserver()
        let count = 30

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< count {
                group.addTask {
                    try await store.perform {
                        await observer.enter()
                        // Yield inside the transaction to widen the reentrancy
                        // window the serialization gate must hold shut.
                        await Task.yield()
                        try await store.setManualDay(DayPresence(
                            date: Date(timeIntervalSince1970: TimeInterval(index) * 86400),
                            in: Self.calendar,
                            regions: [.california],
                        ))
                        await observer.exit()
                    }
                }
            }
            try await group.waitForAll()
        }

        // No two transactions were ever in flight simultaneously...
        #expect(await observer.maxConcurrent == 1)
        // ...and every write committed (the old bug lost or crashed on writes).
        let stored = try await store.allManualDays()
        #expect(stored.count == count)
    }

    @Test func rolledBackWriteDoesNotPingChanges() async throws {
        let store = try SwiftDataStore.inMemory()
        let stream = store.changes()

        // A throwing transaction discards the peer context without saving, so
        // nothing reaches the persistent store and no ping should fire.
        await #expect(throws: CancellationError.self) {
            try await store.perform {
                try await store.setManualDay(self.day)
                throw CancellationError()
            }
        }

        #expect(await !firstPing(stream, within: .milliseconds(200)))
    }

    @Test func recordingDeviceAndPolicyRoundTripWithoutDuplicateLogicalRows() async throws {
        let store = try SwiftDataStore.inMemory()
        let deviceID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        let policyID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let date = Date(timeIntervalSinceReferenceDate: 100)
        let device = RecordingDevice(
            id: deviceID,
            systemName: "iPad",
            nickname: "Home iPad",
            kind: .tablet,
            registeredAt: date,
            lastSeenAt: date,
            archivedAt: nil,
            lastAppliedPolicyChangeID: policyID,
            status: .off,
        )
        let policy = RecordingPolicyChange(
            id: policyID,
            deviceID: deviceID,
            effectiveAt: date,
            isEnabled: false,
        )

        try await store.perform {
            try await store.setRecordingDevice(device)
            try await store.setRecordingDevice(device)
            try await store.addRecordingPolicyChange(policy)
            try await store.addRecordingPolicyChange(policy)
        }

        #expect(try await store.recordingDevices() == [device])
        #expect(try await store.recordingPolicyChanges() == [policy])
    }

    /// A remote import (simulated via a scripted source) pings both the general
    /// read-refresh stream and the remote-only side-effect stream.
    @Test func remoteChangeForwardsToBothChangeStreams() async throws {
        let source = ScriptedStoreRemoteChangeSource()
        // The remote-change wiring is folded into the factory (there's no
        // public `startObservingRemoteChanges` to call), so the store observes
        // `source` from construction.
        let store = try SwiftDataStore.inMemory(remoteChangeSource: source)
        // Subscribe before emitting so the forwarded ping isn't missed.
        let changes = store.changes()
        let remoteChanges = store.remoteChanges()

        source.yield()

        #expect(await firstPing(changes, within: .seconds(2)))
        #expect(await firstPing(remoteChanges, within: .seconds(2)))
    }

    /// Once `perform`'s `peer.save()` returns, the committed write must be
    /// visible to a later read through the main (read) context — the question
    /// raised in review (`send()` after `save()` is only useful if readers then
    /// observe the data). The subtle case is an *update* to a row a prior read
    /// already registered in that long-lived read context, where a stale cached
    /// instance could shadow the new value: insert, read (registering the row),
    /// update the same day, then read again and require the *updated* regions —
    /// not the originally-read ones.
    @Test func committedWriteIsVisibleToALaterRead() async throws {
        let store = try SwiftDataStore.inMemory()
        let date = Date(timeIntervalSince1970: 0)

        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: date,
                in: Self.calendar,
                regions: [.california],
            ))
        }
        let afterInsert = try await store.allManualDays()
        #expect(afterInsert.count == 1)
        #expect(afterInsert.first?.regions == [.california])

        // Same `date` key, so this replaces the row the read above registered.
        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: date,
                in: Self.calendar,
                regions: [.newYork],
            ))
        }
        let afterUpdate = try await store.allManualDays()
        #expect(afterUpdate.count == 1)
        #expect(afterUpdate.first?.regions == [.newYork])
    }

    @Test func auditRoundTripsThroughAManualDay() async throws {
        let store = try SwiftDataStore.inMemory()
        let date = Date(timeIntervalSince1970: 0)
        let audit = ManualEntryAudit(
            recordedAt: Date(timeIntervalSince1970: 1000),
            note: "Filed after reviewing receipts.",
            location: CapturedLocation(
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 8,
                timestamp: Date(timeIntervalSince1970: 990),
            ),
        )

        try await store.perform {
            try await store.setManualDay(
                DayPresence(
                    date: date,
                    in: Self.calendar,
                    regions: [.newYork],
                    isAuthoritative: true,
                    audit: audit,
                ),
            )
        }

        let stored = try await store.allManualDays()
        #expect(stored.first?.audit == audit)
    }

    @Test func auditWithoutLocationRoundTripsAsNoteOnly() async throws {
        let store = try SwiftDataStore.inMemory()
        let date = Date(timeIntervalSince1970: 0)
        let audit = ManualEntryAudit(
            recordedAt: Date(timeIntervalSince1970: 1000),
            note: "No GPS fix was available.",
            location: nil,
        )

        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: date,
                in: Self.calendar,
                regions: [.california],
                audit: audit,
            ))
        }

        let stored = try await store.allManualDays()
        #expect(stored.first?.audit == audit)
        #expect(stored.first?.audit?.location == nil)
    }

    /// An additive backfill can't downgrade an authoritative row's regions, but
    /// its (newer) audit must still win — the trail tracks the latest action.
    @Test func additiveBackfillOverAuthoritativeKeepsIncomingAudit() async throws {
        let store = try SwiftDataStore.inMemory()
        let date = Date(timeIntervalSince1970: 0)
        let firstAudit = ManualEntryAudit(
            recordedAt: Date(timeIntervalSince1970: 100),
            note: "Original override.",
            location: nil,
        )
        let laterAudit = ManualEntryAudit(
            recordedAt: Date(timeIntervalSince1970: 200),
            note: "Later backfill sweep.",
            location: nil,
        )

        try await store.perform {
            try await store.setManualDay(
                DayPresence(
                    date: date,
                    in: Self.calendar,
                    regions: [.california],
                    isAuthoritative: true,
                    audit: firstAudit,
                ),
            )
        }
        try await store.perform {
            try await store.setManualDay(
                DayPresence(
                    date: date,
                    in: Self.calendar,
                    regions: [.newYork],
                    isAuthoritative: false,
                    audit: laterAudit,
                ),
            )
        }

        let stored = try await store.allManualDays()
        #expect(stored.count == 1)
        // Regions can't be downgraded (stays authoritative, unions in the backfill)...
        #expect(stored.first?.isAuthoritative == true)
        #expect(stored.first?.regions == [.california, .newYork])
        // ...but the newer audit wins.
        #expect(stored.first?.audit == laterAudit)
    }
}

/// Tracks the peak number of concurrently-executing transaction blocks so a
/// test can assert `perform` serialized them (peak of 1). `enter`/`exit`
/// bracket the block body.
private actor ConcurrencyObserver {
    private var current = 0
    private(set) var maxConcurrent = 0

    func enter() {
        current += 1
        maxConcurrent = max(maxConcurrent, current)
    }

    func exit() {
        current -= 1
    }
}

/// Awaits the first `changes()` ping, returning `false` if none arrives within
/// `budget`. Races the stream against a timeout so a missing ping fails fast
/// instead of hanging the test.
private func firstPing(_ stream: AsyncStream<Void>, within budget: Duration) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in stream {
                return true
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: budget)
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}
