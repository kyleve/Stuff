import Foundation
import Testing
import WhereCore

struct WhereControllerTests {
    private static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private static func makeAggregator() -> DayAggregator {
        DayAggregator(calendar: Calendar(identifier: .gregorian), timeZone: pacific)
    }

    private static func makeController() throws
        -> (WhereController, SwiftDataStore, ScriptedLocationSource)
    {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource()
        let controller = WhereController(
            store: store,
            locationSource: source,
            aggregator: makeAggregator(),
        )
        return (controller, store, source)
    }

    @Test func ingestStoresSamplesAndReportsThem() async throws {
        let (controller, _, _) = try Self.makeController()
        let sf = LocationSample(
            timestamp: iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        )
        try await controller.ingest(sf)

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.count == 1)
        #expect(report.days.first?.regions == [.california])
        #expect(report.totals == [.california: 1])
    }

    @Test func manualDayUnionsWithSamples() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.ingest(LocationSample(
            timestamp: iso("2026-07-04T10:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        ))
        try await controller.addManualDay(
            date: iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )

        let report = try await controller.yearReport(for: 2026)
        let july4 = report.days.first { day in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
            let components = cal.dateComponents([.month, .day], from: day.date)
            return components.month == 7 && components.day == 4
        }
        #expect(july4?.regions == [.california, .newYork])
    }

    @Test func manualDayReplacesOnSecondCall() async throws {
        let (controller, _, _) = try Self.makeController()
        let date = iso("2026-07-04T15:00:00-07:00")
        try await controller.addManualDay(date: date, regions: [.california])
        try await controller.addManualDay(date: date, regions: [.newYork])

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.count == 1)
        // Second call should replace, not union, when there are no
        // GPS samples on the day — proves the store-level upsert on
        // `setManualDay` (not a delete-then-insert that would let
        // duplicates accumulate).
        #expect(report.days.first?.regions == [.newYork])
    }

    @Test func addManualDaysBackfillsEveryDayInRange() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.addManualDays(
            from: iso("2026-02-10T09:00:00-08:00"),
            through: iso("2026-02-14T20:00:00-08:00"),
            regions: [.newYork],
        )

        let report = try await controller.yearReport(for: 2026)
        // Feb 10–14 inclusive is five days, each attributed to New York.
        #expect(report.days.count == 5)
        #expect(report.totals == [.newYork: 5])
        #expect(report.days.allSatisfy { $0.regions == [.newYork] })
    }

    @Test func addManualDaysWithStartAfterEndWritesNothing() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.addManualDays(
            from: iso("2026-02-14T00:00:00-08:00"),
            through: iso("2026-02-10T00:00:00-08:00"),
            regions: [.california],
        )

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.isEmpty)
        #expect(report.totals.isEmpty)
    }

    @Test func addManualDaysSameStartAndEndWritesOneDay() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.addManualDays(
            from: iso("2026-02-10T06:00:00-08:00"),
            through: iso("2026-02-10T23:00:00-08:00"),
            regions: [.california],
        )

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.count == 1)
        #expect(report.totals == [.california: 1])
    }

    @Test func clearYearWipesAndReportsEmpty() async throws {
        let (controller, _, _) = try Self.makeController()
        try await controller.ingest(LocationSample(
            timestamp: iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        ))
        try await controller.clearYear(2026)
        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.isEmpty)
        #expect(report.totals.isEmpty)
    }

    @Test func gpsFailuresEnqueueAndDrainOnRecovery() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource()
        let controller = WhereController(
            store: store,
            locationSource: source,
            aggregator: Self.makeAggregator(),
        )
        await controller.startGPS()

        let sampleA = LocationSample(
            timestamp: iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        let sampleB = LocationSample(
            timestamp: iso("2026-03-15T12:05:00-07:00"),
            coordinate: Coordinate(latitude: 37.7750, longitude: -122.4195),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        await store.setShouldFail(true)
        source.emit(sampleA)
        source.emit(sampleB)
        try await waitUntil { await controller.retryQueueDepth == 2 }
        #expect(await store.persistedCount == 0)

        await store.setShouldFail(false)
        let sampleC = LocationSample(
            timestamp: iso("2026-03-15T12:10:00-07:00"),
            coordinate: Coordinate(latitude: 37.7751, longitude: -122.4196),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        source.emit(sampleC)
        try await waitUntil { await controller.retryQueueDepth == 0 }
        #expect(await store.persistedCount == 3)

        await controller.stopGPS()
    }

    @Test func trackingResumesAfterPauseWithoutDroppingSamples() async throws {
        let (controller, _, source) = try Self.makeController()

        await controller.startGPS()
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { try await controller.yearReport(for: 2026).days.count == 1 }

        // Pause, then resume. A naive implementation cancels the stream
        // consumer here, leaving the resumed session iterating a finished
        // stream so this second sample would be silently dropped.
        await controller.stopGPS()
        let pausedActive = await controller.isTrackingActive
        #expect(!pausedActive)
        await controller.startGPS()
        let resumedActive = await controller.isTrackingActive
        #expect(resumedActive)

        source.emit(sample(at: "2026-03-16T12:00:00-07:00"))
        try await waitUntil { try await controller.yearReport(for: 2026).days.count == 2 }

        await controller.stopGPS()
    }

    @Test func performThrow_rollsBackEntireTransaction() async throws {
        let store = try SwiftDataStore.inMemory()
        let s1 = sample(at: "2026-04-10T08:00:00-07:00")
        let s2 = sample(at: "2026-04-10T09:00:00-07:00")

        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await store.perform {
                try await store.add(sample: s1)
                try await store.add(sample: s2)
                throw Boom()
            }
        }

        let persisted = try await store.allSamples()
        #expect(persisted.isEmpty, "throwing perform should roll back every staged write")
    }

    @Test func performSuccess_writesAreVisibleToReadersAfterReturn() async throws {
        let store = try SwiftDataStore.inMemory()
        let s = sample(at: "2026-04-10T08:00:00-07:00")

        try await store.perform { try await store.add(sample: s) }

        let persisted = try await store.allSamples()
        #expect(persisted == [s], "saved peer changes should be visible to the main read context")
    }

    @Test func readsInsidePerform_seePendingWritesOnPeer() async throws {
        let store = try SwiftDataStore.inMemory()
        let s = sample(at: "2026-04-10T08:00:00-07:00")

        let countSeenInsidePerform = try await store.perform { () -> Int in
            try await store.add(sample: s)
            return try await store.allSamples().count
        }
        #expect(
            countSeenInsidePerform == 1,
            "in-flight peer writes should be readable inside the same perform",
        )
    }

    private func sample(at isoString: String) -> LocationSample {
        LocationSample(
            id: UUID(),
            timestamp: iso(isoString),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .manual,
        )
    }

    @Test func evidenceRoundTripsViaController() async throws {
        let (controller, _, _) = try Self.makeController()
        let evidence = Evidence(
            kind: .planeTicket,
            capturedAt: iso("2026-04-10T08:00:00-07:00"),
            region: .california,
            note: "SFO → JFK",
            contentType: .plainText,
        )
        let blob = Data("ticket pdf".utf8)
        try await controller.addEvidence(evidence, blob: blob)

        let fetched = try await controller.evidence(for: 2026)
        #expect(fetched == [evidence])

        let fetchedBlob = try await controller.evidenceBlob(for: evidence.id)
        #expect(fetchedBlob == blob)
    }

    // MARK: - Backup

    private static let backupEvidence = Evidence(
        id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        kind: .boardingPass,
        capturedAt: Date(timeIntervalSince1970: 1_700_050_000),
        region: .california,
        note: "SFO → JFK",
        contentType: .pdf,
    )
    private static let backupBlob = Data("boarding-pass-pdf".utf8)

    /// Seed a controller's store with one sample, one evidence (with a blob),
    /// and one manual day so backup tests have all three tables populated.
    private func seedBackupData(_ controller: WhereController) async throws {
        try await controller.ingest(sample(at: "2026-03-15T12:00:00-07:00"))
        try await controller.addEvidence(Self.backupEvidence, blob: Self.backupBlob)
        try await controller.addManualDay(
            date: iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )
    }

    @Test func backupExportThenMergeImportReproducesEveryTable() async throws {
        let (source, sourceStore, _) = try Self.makeController()
        try await seedBackupData(source)

        let url = try await source.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (destination, destinationStore, _) = try Self.makeController()
        let summary = try await destination.importBackup(from: url, strategy: .merge)

        #expect(summary.sampleCount == 1)
        #expect(summary.evidenceCount == 1)
        #expect(summary.manualDayCount == 1)

        #expect(try await destinationStore.allSamples() == sourceStore.allSamples())
        #expect(try await destinationStore.allEvidence() == sourceStore.allEvidence())
        #expect(try await destinationStore.allManualDays() == sourceStore.allManualDays())
        #expect(
            try await destinationStore.evidenceBlob(for: Self.backupEvidence.id) == Self.backupBlob,
        )
    }

    @Test func backupMergeImportKeepsPreexistingRows() async throws {
        let (source, _, _) = try Self.makeController()
        try await seedBackupData(source)
        let url = try await source.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (destination, destinationStore, _) = try Self.makeController()
        // A row that exists only on the destination and is absent from the
        // backup; merge must leave it in place.
        let preexisting = sample(at: "2026-01-01T09:00:00-08:00")
        try await destination.addManualSample(preexisting)

        _ = try await destination.importBackup(from: url, strategy: .merge)

        let ids = try await destinationStore.allSamples().map(\.id)
        #expect(ids.contains(preexisting.id))
        #expect(ids.count == 2)
    }

    @Test func backupReplaceImportWipesPreexistingRows() async throws {
        let (source, sourceStore, _) = try Self.makeController()
        try await seedBackupData(source)
        let url = try await source.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (destination, destinationStore, _) = try Self.makeController()
        // Pre-existing destination data that the backup does not contain.
        try await destination.addManualSample(sample(at: "2026-01-01T09:00:00-08:00"))
        try await destination.addManualDay(
            date: iso("2026-02-02T10:00:00-08:00"),
            regions: [.canada],
        )

        _ = try await destination.importBackup(from: url, strategy: .replace)

        // The store now mirrors the backup exactly — none of the pre-existing
        // rows survive.
        #expect(try await destinationStore.allSamples() == sourceStore.allSamples())
        #expect(try await destinationStore.allManualDays() == sourceStore.allManualDays())
    }

    @Test func clearAll_removesEveryTable() async throws {
        let store = try SwiftDataStore.inMemory()
        let seedSample = sample(at: "2026-03-15T12:00:00-07:00")
        let seedDay = DayPresence(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            regions: [.california],
        )
        try await store.perform {
            try await store.add(sample: seedSample)
            try await store.write(evidence: Self.backupEvidence, blob: Self.backupBlob)
            try await store.setManualDay(seedDay)
        }

        try await store.perform { try await store.clearAll() }

        #expect(try await store.allSamples().isEmpty)
        #expect(try await store.allEvidence().isEmpty)
        #expect(try await store.allManualDays().isEmpty)
    }
}

private func iso(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: string) ?? Date(timeIntervalSince1970: 0)
}

@Sendable
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @Sendable () async throws -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("waitUntil timed out")
}

private struct ToggleFailingStoreError: Error {}

/// `WhereStore` that lets a test toggle whether `add(sample:)` succeeds.
/// Every other API forwards to a real `SwiftDataStore` (in-memory) so
/// reads stay deterministic and the failure injection point stays
/// narrow.
private actor ToggleFailingStore: WhereStore {
    private let backing: SwiftDataStore
    private var shouldFail = false

    init(backing: SwiftDataStore) {
        self.backing = backing
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    var persistedCount: Int {
        get async {
            await (try? backing.allSamples().count) ?? 0
        }
    }

    func perform<T: Sendable>(
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        try await backing.perform(block)
    }

    func add(sample: LocationSample) async throws {
        if shouldFail { throw ToggleFailingStoreError() }
        try await backing.add(sample: sample)
    }

    func samples(in interval: DateInterval) async throws -> [LocationSample] {
        try await backing.samples(in: interval)
    }

    func allSamples() async throws -> [LocationSample] {
        try await backing.allSamples()
    }

    func write(evidence: Evidence, blob: Data?) async throws {
        try await backing.write(evidence: evidence, blob: blob)
    }

    func evidence(in interval: DateInterval) async throws -> [Evidence] {
        try await backing.evidence(in: interval)
    }

    func allEvidence() async throws -> [Evidence] {
        try await backing.allEvidence()
    }

    func evidenceBlob(for id: UUID) async throws -> Data? {
        try await backing.evidenceBlob(for: id)
    }

    func setManualDay(_ day: DayPresence) async throws {
        try await backing.setManualDay(day)
    }

    func manualDays(in interval: DateInterval) async throws -> [DayPresence] {
        try await backing.manualDays(in: interval)
    }

    func allManualDays() async throws -> [DayPresence] {
        try await backing.allManualDays()
    }

    func clear(in interval: DateInterval) async throws {
        try await backing.clear(in: interval)
    }

    func clearAll() async throws {
        try await backing.clearAll()
    }
}
