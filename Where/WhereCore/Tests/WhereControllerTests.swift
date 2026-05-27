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

    @Test func evidenceRoundTripsViaController() async throws {
        let (controller, _, _) = try Self.makeController()
        let evidence = Evidence(
            kind: .planeTicket,
            capturedAt: iso("2026-04-10T08:00:00-07:00"),
            region: .california,
            note: "SFO → JFK",
        )
        let blob = Data("ticket pdf".utf8)
        try await controller.addEvidence(evidence, blob: blob)

        let fetched = try await controller.evidence(for: 2026)
        #expect(fetched == [evidence])

        let fetchedBlob = try await controller.evidenceBlob(for: evidence.id)
        #expect(fetchedBlob == blob)
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

/// `WhereStore` that lets a test toggle whether `addSample` succeeds.
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

    func addSample(_ sample: LocationSample) async throws {
        if shouldFail { throw ToggleFailingStoreError() }
        try await backing.addSample(sample)
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

    func evidenceBlob(for id: UUID) async throws -> Data? {
        try await backing.evidenceBlob(for: id)
    }

    func setManualDay(_ day: DayPresence) async throws {
        try await backing.setManualDay(day)
    }

    func manualDays(in interval: DateInterval) async throws -> [DayPresence] {
        try await backing.manualDays(in: interval)
    }

    func clear(in interval: DateInterval) async throws {
        try await backing.clear(in: interval)
    }
}
