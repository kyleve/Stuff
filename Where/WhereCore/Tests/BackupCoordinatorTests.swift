import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Covers export/import round-trips and the post-import `onImport` hook the
/// coordinator invokes once new data lands.
struct BackupCoordinatorTests {
    private struct Harness {
        let coordinator: BackupCoordinator
        let store: SwiftDataStore
        let onImport: HookSpy
    }

    /// Records how many times the coordinator invoked its `onImport` hook, so a
    /// test can assert an import triggers the (composition-root-supplied)
    /// badge / notification / widget reconcile exactly once.
    private actor HookSpy {
        private(set) var count = 0
        func run() {
            count += 1
        }
    }

    private static func makeHarness() throws -> Harness {
        let store = try SwiftDataStore.inMemory()
        let hook = HookSpy()
        let coordinator = BackupCoordinator(
            store: store,
            onImport: { await hook.run() },
        )
        return Harness(coordinator: coordinator, store: store, onImport: hook)
    }

    private static let evidence = Evidence(
        id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        kind: .boardingPass,
        capturedAt: Date(timeIntervalSince1970: 1_700_050_000),
        region: .california,
        note: "SFO → JFK",
        contentType: .pdf,
    )
    private static let blob = Data("boarding-pass-pdf".utf8)

    private static let dismissal = DismissedIssue(
        id: .borderDrift(day: CalendarDay(year: 2026, month: 4, day: 1)),
        dismissedAt: Date(timeIntervalSince1970: 1_700_000_000),
    )
    private static let recordingDeviceID = RecordingDeviceID(
        rawValue: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
    )
    private static let recordingPolicyID =
        UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

    /// Seed every persisted domain directly into a store so backup tests don't
    /// depend on the journal or recording controller.
    private static func seed(_ store: SwiftDataStore) async throws {
        try await store.perform {
            try await store.add(sample: sample(at: "2026-03-15T12:00:00-07:00"))
            try await store.write(evidence: evidence, blob: blob)
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-07-04T00:00:00-07:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.newYork],
            ))
            try await store.restoreDismissedIssue(dismissal)
            try await store.setRecordingDevice(RecordingDevice(
                id: recordingDeviceID,
                systemName: "iPad",
                nickname: "Travel iPad",
                kind: .tablet,
                registeredAt: dismissal.dismissedAt,
                lastSeenAt: dismissal.dismissedAt,
                archivedAt: nil,
                lastAppliedPolicyChangeID: recordingPolicyID,
                status: .recording,
            ))
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: recordingPolicyID,
                deviceID: recordingDeviceID,
                effectiveAt: dismissal.dismissedAt,
                isEnabled: true,
            ))
        }
    }

    @Test func exportThenMergeImportReproducesEveryTable() async throws {
        let source = try Self.makeHarness()
        try await Self.seed(source.store)

        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        let summary = try await destination.coordinator.importBackup(from: url, strategy: .merge)

        #expect(summary.sampleCount == 1)
        #expect(summary.evidenceCount == 1)
        #expect(summary.manualDayCount == 1)
        #expect(summary.dismissedIssueCount == 1)
        #expect(summary.recordingDeviceCount == 1)
        #expect(summary.recordingPolicyChangeCount == 1)

        #expect(try await destination.store.allSamples() == source.store.allSamples())
        #expect(try await destination.store.allEvidence() == source.store.allEvidence())
        #expect(try await destination.store.allManualDays() == source.store.allManualDays())
        // Dismissals come back verbatim (id + original timestamp).
        #expect(try await destination.store.allDismissedIssues() == source.store
            .allDismissedIssues())
        #expect(try await destination.store.allDismissedIssues() == [Self.dismissal])
        #expect(try await destination.store.recordingDevices() == source.store.recordingDevices())
        #expect(try await destination.store.recordingPolicyChanges() == source.store
            .recordingPolicyChanges())
        #expect(try await destination.store.evidenceBlob(for: Self.evidence.id) == Self.blob)
        // An import that lands new data runs the post-import hook once.
        #expect(await destination.onImport.count == 1)
    }

    @Test func mergeImportKeepsPreexistingRows() async throws {
        let source = try Self.makeHarness()
        try await Self.seed(source.store)
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        let preexisting = Self.sample(at: "2026-01-01T09:00:00-08:00")
        try await destination.store.perform { try await destination.store.add(sample: preexisting) }

        _ = try await destination.coordinator.importBackup(from: url, strategy: .merge)

        let ids = try await destination.store.allSamples().map(\.id)
        #expect(ids.contains(preexisting.id))
        #expect(ids.count == 2)
    }

    @Test func replaceImportWipesPreexistingRows() async throws {
        let source = try Self.makeHarness()
        try await Self.seed(source.store)
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        try await destination.store.perform {
            try await destination.store.add(sample: Self.sample(at: "2026-01-01T09:00:00-08:00"))
            try await destination.store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-02-02T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.canada],
            ))
            // A preexisting dismissal that the file doesn't contain must be wiped
            // by `.replace` so the device mirrors the file exactly.
            try await destination.store.restoreDismissedIssue(DismissedIssue(
                id: .missingDays(start: CalendarDay(year: 2026, month: 1, day: 2)),
                dismissedAt: Date(timeIntervalSince1970: 1),
            ))
        }

        _ = try await destination.coordinator.importBackup(from: url, strategy: .replace)

        #expect(try await destination.store.allSamples() == source.store.allSamples())
        #expect(try await destination.store.allManualDays() == source.store.allManualDays())
        #expect(try await destination.store.allDismissedIssues() == source.store
            .allDismissedIssues())
        #expect(try await destination.store.allDismissedIssues() == [Self.dismissal])
    }

    @Test func replaceImportRestoresTheArchivesTrackedRegions() async throws {
        let source = try Self.makeHarness()
        let texas = try #require(Region(rawValue: "us-TX"))
        try await source.store.perform {
            try await source.store.setTrackedRegion(true, id: Region.california.rawValue)
            try await source.store.setTrackedRegion(true, id: texas.rawValue)
        }
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        let summary = try await destination.coordinator.importBackup(from: url, strategy: .replace)

        #expect(summary.trackedRegionCount == 2)
        #expect(try await destination.store.trackedRegions() == [.california, texas])
    }

    @Test func importRestoresPickedRegionAppearance() async throws {
        let source = try Self.makeHarness()
        let caLook = RegionAppearance(color: .orange, emoji: "🌴", symbolName: "sun.max.fill")
        try await source.store.perform {
            try await source.store.setPrimaryRegions([
                PrimaryRegion(region: .california, appearance: caLook, order: 0),
            ])
        }
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        _ = try await destination.coordinator.importBackup(from: url, strategy: .replace)

        let restored = try await destination.store.primaryRegions()
        #expect(restored.map(\.region) == [.california])
        #expect(restored.first?.appearance == caLook)
    }

    @Test func mergeImportKeepsCustomizedLookWhenArchiveAppearanceIsNil() async throws {
        // The device customized California; the archive tracks it with no picked
        // look. A merge must not clobber the device's look with the archive's nil.
        let caLook = RegionAppearance(color: .orange, emoji: "🌴", symbolName: "sun.max.fill")
        let source = try Self.makeHarness()
        try await source.store.perform {
            try await source.store.setPrimaryRegions([
                PrimaryRegion(region: .california, appearance: nil, order: 0),
            ])
        }
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        try await destination.store.perform {
            try await destination.store.setPrimaryRegions([
                PrimaryRegion(region: .california, appearance: caLook, order: 0),
            ])
        }
        _ = try await destination.coordinator.importBackup(from: url, strategy: .merge)

        let restored = try await destination.store.primaryRegions()
        #expect(restored.map(\.region) == [.california])
        #expect(restored.first?.appearance == caLook)
    }

    @Test func mergeImportOverwritesLookWhenArchiveHasAppearanceAndAppendsNewRegions() async throws {
        let texas = try #require(Region(rawValue: "us-TX"))
        let archiveCALook = RegionAppearance(
            color: .indigo,
            emoji: "🌉",
            symbolName: "building.2.fill",
        )
        let txLook = RegionAppearance(color: .red, emoji: "🤠", symbolName: "star.fill")
        let source = try Self.makeHarness()
        try await source.store.perform {
            try await source.store.setPrimaryRegions([
                PrimaryRegion(region: .california, appearance: archiveCALook, order: 0),
                PrimaryRegion(region: texas, appearance: txLook, order: 1),
            ])
        }
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        let deviceCALook = RegionAppearance(color: .orange, emoji: "🌴", symbolName: "sun.max.fill")
        try await destination.store.perform {
            try await destination.store.setPrimaryRegions([
                PrimaryRegion(region: .california, appearance: deviceCALook, order: 0),
            ])
        }
        _ = try await destination.coordinator.importBackup(from: url, strategy: .merge)

        let restored = try await destination.store.primaryRegions()
        // Existing region stays first; archive's look wins on overlap; the
        // archive-only region is appended with its look.
        #expect(restored.map(\.region) == [.california, texas])
        #expect(restored.first?.appearance == archiveCALook)
        #expect(restored.last?.appearance == txLook)
    }

    @Test func mergeImportUnionsTrackedRegionsWithTheExisting() async throws {
        let source = try Self.makeHarness()
        let texas = try #require(Region(rawValue: "us-TX"))
        try await source.store.perform {
            try await source.store.setTrackedRegion(true, id: texas.rawValue)
        }
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        try await destination.store.perform {
            try await destination.store.setTrackedRegion(true, id: Region.california.rawValue)
        }
        _ = try await destination.coordinator.importBackup(from: url, strategy: .merge)

        // Merge unions the archive's set into the device's existing selection.
        #expect(try await destination.store.trackedRegions() == [.california, texas])
    }

    /// Regression guard: an import rewrites day data, so the coordinator must
    /// invoke its `onImport` hook once new data lands — the composition root
    /// wires that hook to the badge / notification / widget reconcile, so
    /// skipping it leaves the home-screen badge and issues alert stuck at their
    /// pre-import values (the "badge stuck at 157 after replace import" bug).
    /// The end-to-end badge recount is asserted in `WhereServicesTests`.
    @Test func replaceImportInvokesTheOnImportHook() async throws {
        let source = try Self.makeHarness()
        try await Self.seed(source.store)
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        #expect(await destination.onImport.count == 0)

        _ = try await destination.coordinator.importBackup(from: url, strategy: .replace)

        #expect(await destination.onImport.count == 1)
    }

    /// The coordinator owns the export staging directory's lifecycle: starting a
    /// new export purges the previous one, so at most one archive sits on disk.
    @Test func exportPurgesThePreviousExportDirectory() async throws {
        let harness = try Self.makeHarness()
        try await Self.seed(harness.store)

        let first = try await harness.coordinator.exportBackup()
        let firstDirectory = first.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: first.path))

        let second = try await harness.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: second.deletingLastPathComponent()) }

        #expect(!FileManager.default.fileExists(atPath: firstDirectory.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func discardExportDeletesTheExportDirectory() async throws {
        let harness = try Self.makeHarness()
        try await Self.seed(harness.store)

        let url = try await harness.coordinator.exportBackup()
        let directory = url.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: url.path))

        await harness.coordinator.discardExport()
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        // Idempotent: a second discard (nothing left to reclaim) is a no-op.
        await harness.coordinator.discardExport()
    }

    @Test func exportReportsProgressUpToCompletion() async throws {
        let source = try Self.makeHarness()
        try await Self.seed(source.store)

        let recorder = ProgressRecorder()
        let url = try await source.coordinator.exportBackup { fraction in
            recorder.record(fraction)
        }
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let fractions = recorder.fractions
        #expect(!fractions.isEmpty)
        #expect(fractions.allSatisfy { $0 > 0 && $0 <= 1 })
        #expect(fractions.last == 1)
    }

    @Test func importReportsProgressUpToCompletion() async throws {
        let source = try Self.makeHarness()
        try await Self.seed(source.store)
        let url = try await source.coordinator.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destination = try Self.makeHarness()
        let recorder = ProgressRecorder()
        _ = try await destination.coordinator
            .importBackup(from: url, strategy: .replace) { fraction in
                recorder.record(fraction)
            }

        let fractions = recorder.fractions
        #expect(!fractions.isEmpty)
        #expect(fractions.allSatisfy { $0 > 0 && $0 <= 1 })
        #expect(fractions.last == 1)
    }

    private final class ProgressRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        func record(_ value: Double) {
            lock.withLock { values.append(value) }
        }

        var fractions: [Double] {
            lock.withLock { values }
        }
    }

    private static func sample(at isoString: String) -> LocationSample {
        LocationSample(
            id: UUID(),
            timestamp: WhereCoreTestSupport.iso(isoString),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .manual,
        )
    }
}
