import Foundation
import Synchronization
import Testing
@_spi(Testing) @testable import WhereCore

@MainActor
struct WidgetDataAccessTests {
    private let directory: URL
    private let snapshot = WidgetSnapshot(
        day: Date(timeIntervalSince1970: 1_700_000_000),
        year: 2026,
        dayRegions: [.california],
        totals: [.california: 12],
    )

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func cleanup() {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record(error) }
    }

    @Test func readingRequiresVerifiedEvidenceAndMatchingPayloadProvenance() throws {
        defer { cleanup() }
        let access = AppGroupDataAccess(directory: directory)
        let snapshots = WidgetSnapshotStore(directory: directory)
        try snapshots.write(.init(snapshot: snapshot, version: .baseline, domain: .local))
        #expect(throws: DataCompatibilityFailure.self) {
            try access.readWidgetSnapshot(version: .baseline)
        }
        try access.save(.init(
            domain: .local,
            version: .baseline,
            access: .verified,
            removedDeviceID: nil,
        ))
        #expect(try access.readWidgetSnapshot(version: .baseline) == snapshot)
        try access.save(.init(
            domain: .local,
            version: .baseline,
            access: .blocked,
            removedDeviceID: nil,
        ))
        #expect(throws: DataCompatibilityFailure.self) {
            try access.readWidgetSnapshot(version: .baseline)
        }
        try access.save(.init(
            domain: .local,
            version: .init(rawValue: 2),
            access: .verified,
            removedDeviceID: nil,
        ))
        #expect(throws: DataCompatibilityFailure.self) {
            try access.readWidgetSnapshot(version: .baseline)
        }
        #expect(throws: DataCompatibilityTransportError.self) {
            try access.readWidgetSnapshot(version: .init(rawValue: 2))
        }
        try access.save(.init(
            domain: .cloud(.init(containerIdentifier: "iCloud.test", userRecordName: "other")),
            version: .baseline,
            access: .verified,
            removedDeviceID: nil,
        ))
        #expect(throws: DataCompatibilityTransportError.self) {
            try access.readWidgetSnapshot(version: .baseline)
        }
    }

    @Test func legacyOrMissingPayloadIsAnEmptyCacheAfterVerification() throws {
        defer { cleanup() }
        let access = AppGroupDataAccess(directory: directory)
        try access.save(.init(
            domain: .local,
            version: .baseline,
            access: .verified,
            removedDeviceID: nil,
        ))
        #expect(try access.readWidgetSnapshot(version: .baseline) == nil)
        try JSONEncoder().encode(snapshot)
            .write(to: directory.appending(path: "widget-snapshot.json"))
        #expect(try access.readWidgetSnapshot(version: .baseline) == nil)
        try access.writeWidgetSnapshot(snapshot, version: .baseline, domain: .local)
        #expect(try access.readWidgetSnapshot(version: .baseline) == snapshot)
    }

    @Test(arguments: [true, false])
    func receiptChangeDuringReadRejectsEvidence(hasSnapshot: Bool) throws {
        defer { cleanup() }
        let snapshots = WidgetSnapshotStore(directory: directory)
        if hasSnapshot {
            try snapshots.write(.init(snapshot: snapshot, version: .baseline, domain: .local))
        }
        let reader = CompatibleWidgetSnapshotReader(
            access: ChangingWidgetAccess(
                before: .init(
                    domain: .local,
                    version: .baseline,
                    access: .verified,
                    removedDeviceID: nil,
                ),
                after: .init(
                    domain: .cloud(.init(
                        containerIdentifier: "iCloud.test",
                        userRecordName: "other",
                    )),
                    version: .baseline,
                    access: .verified,
                    removedDeviceID: nil,
                ),
            ),
            snapshots: snapshots,
        )
        #expect(throws: DataCompatibilityTransportError.self) { try reader.read(version: .baseline)
        }
    }

    @Test func retiredPublisherCannotOverwriteTheRecoveredScopesSnapshot() async throws {
        defer { cleanup() }
        let access = AppGroupDataAccess(directory: directory)
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: access,
            version: .baseline,
        )
        await coordinator.refresh { .disabled }
        let reloader = CountingWidgetReloader()
        let old = try WidgetCenterTimelineRefresher(
            access: access,
            coordinator: coordinator,
            admission: coordinator.requireAccess(),
            reloader: reloader,
        )
        await old.publish(snapshot)
        #expect(try access.readWidgetSnapshot(version: .baseline) == snapshot)
        await transport.changeAccount()
        try await waitForCompatibility { coordinator.state.allowsStore == false }
        await coordinator.refresh { .disabled }
        let current = try WidgetCenterTimelineRefresher(
            access: access,
            coordinator: coordinator,
            admission: coordinator.requireAccess(),
            reloader: reloader,
        )
        let replacement = WidgetSnapshot(
            day: snapshot.day,
            year: snapshot.year,
            dayRegions: [.newYork],
            totals: [.newYork: 3],
        )
        await current.publish(replacement)
        await old.publish(snapshot)
        #expect(try access.readWidgetSnapshot(version: .baseline) == replacement)
        #expect(reloader.count == 3)
    }
}

private final class ChangingWidgetAccess: DataCompatibilityAccessChecking {
    let before: DataCompatibilityReceipt
    let after: DataCompatibilityReceipt
    private let reads = Mutex(0)

    init(before: DataCompatibilityReceipt, after: DataCompatibilityReceipt) {
        self.before = before
        self.after = after
    }

    func requireAccess(version: DataModelVersion) throws -> DataCompatibilityReceipt {
        let receipt = reads.withLock { count in
            defer { count += 1 }
            return count == 0 ? before : after
        }
        try receipt.requireAccess(version: version)
        return receipt
    }
}

private final class CountingWidgetReloader: WidgetTimelineReloading {
    private let calls = Mutex(0)
    var count: Int {
        calls.withLock { $0 }
    }

    func reload() {
        calls.withLock { $0 += 1 }
    }
}
