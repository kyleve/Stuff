import Foundation
import Testing
@testable import WhereCore

/// Covers the GPS ingestion lifecycle, the post-persist hook, and the retry
/// queue the controller delegates all of `startGPS`/`stopGPS`/auth to.
struct LocationIngestorTests {
    private static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar
    }

    private actor OutcomeRecorder {
        private(set) var outcomes: [LocationIngestor.IngestOutcome] = []

        func record(_ outcome: LocationIngestor.IngestOutcome) {
            outcomes.append(outcome)
        }

        var count: Int {
            outcomes.count
        }

        var last: LocationIngestor.IngestOutcome? {
            outcomes.last
        }
    }

    /// In-memory stand-in for the durable outbox: `load()` returns whatever was
    /// last `save`d, so two ingestors sharing one instance models the on-disk
    /// backlog surviving a relaunch.
    private actor SpyLocationOutbox: LocationOutbox {
        private(set) var contents: [LocationSample]

        init(_ contents: [LocationSample] = []) {
            self.contents = contents
        }

        func load() async -> [LocationSample] {
            contents
        }

        func save(_ samples: [LocationSample]) async {
            contents = samples
        }
    }

    private static func makeIngestor(
        store: any WhereStore,
        source: ScriptedLocationSource,
        recorder: OutcomeRecorder,
        outbox: any LocationOutbox = NoOpLocationOutbox(),
    ) -> LocationIngestor {
        LocationIngestor(
            store: store,
            locationSource: source,
            calendar: calendar(),
            outbox: outbox,
            onPersisted: { outcome in await recorder.record(outcome) },
        )
    }

    @Test func startActivatesMonitoringAndStopPauses() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)

        await ingestor.start()
        #expect(await ingestor.isActive)
        // The resume path fires a (drain-only) outcome even with an empty queue.
        #expect(await recorder.count == 1)
        #expect(await recorder.last?.liveSample == nil)

        await ingestor.stop()
        #expect(await !(ingestor.isActive))
    }

    @Test func liveSampleIsPersistedAndReported() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        await ingestor.start()

        source.emit(LocationSample(
            timestamp: iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        ))

        try await waitUntil { await recorder.count >= 2 }
        #expect(await recorder.last?.liveSample != nil)
        #expect(try await store.allSamples().count == 1)
    }

    @Test func failedPersistEnqueuesThenLaterDrains() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        await ingestor.start()

        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }

        // A later successful ingest drains the backlog before persisting itself.
        // Wait on the durable outcome (both samples committed) rather than
        // `retryQueueDepth == 0`: the drain clears the queue *before* it commits
        // the re-persists, so the depth hitting zero doesn't yet mean the data
        // has landed.
        await store.setShouldFail(false)
        source.emit(sample(at: "2026-03-15T13:00:00-07:00"))
        try await waitUntil { await (try? backing.allSamples().count) == 2 }
        #expect(await ingestor.retryQueueDepth == 0)
    }

    @Test func quiesceClearsTheRetryQueue() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        await ingestor.start()

        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }

        // Quiescing for a teardown drops the backlog so a later start() can't
        // re-drain those samples into the freshly wiped store.
        await ingestor.quiesce()
        #expect(await ingestor.retryQueueDepth == 0)
        #expect(await !(ingestor.isActive))
    }

    @Test func quiesceStopsPersistingFurtherSamples() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        await ingestor.start()

        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        // start() fires one drain-only outcome; the live sample fires a second.
        try await waitUntil { await recorder.count >= 2 }
        #expect(try await store.allSamples().count == 1)

        await ingestor.quiesce()

        // A sample delivered after quiesce (e.g. a buffered event arriving mid
        // teardown) must not be persisted, so it can't clobber the wipe that
        // follows.
        source.emit(sample(at: "2026-03-15T13:00:00-07:00"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await store.allSamples().count == 1)
    }

    @Test func failedPersistMirrorsToTheDurableOutbox() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let outbox = SpyLocationOutbox()
        let ingestor = Self.makeIngestor(
            store: store,
            source: source,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        await ingestor.start()

        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }

        // The failed sample is mirrored durably, not just held in memory — so it
        // can be recovered if the process dies before the next successful save.
        #expect(await outbox.contents.count == 1)
    }

    @Test func durableBacklogDrainsOnTheNextLaunch() async throws {
        let backing = try SwiftDataStore.inMemory()
        let failing = ToggleFailingStore(backing: backing)
        let outbox = SpyLocationOutbox()

        // First launch: the store is down, so the sample lands only in the
        // durable backlog (the app could now be killed).
        let source1 = ScriptedLocationSource(authorizationStatus: .always)
        let ingestor1 = Self.makeIngestor(
            store: failing,
            source: source1,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        await ingestor1.start()
        await failing.setShouldFail(true)
        source1.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor1.retryQueueDepth == 1 }
        #expect(await outbox.contents.count == 1)

        // Second launch: a brand-new ingestor over the *same* durable outbox and
        // a now-healthy store drains the backlog on start() — no data lost.
        let source2 = ScriptedLocationSource(authorizationStatus: .always)
        let ingestor2 = Self.makeIngestor(
            store: backing,
            source: source2,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        await ingestor2.start()

        try await waitUntil { await (try? backing.allSamples().count) == 1 }
        #expect(await ingestor2.retryQueueDepth == 0)
        #expect(await outbox.contents.isEmpty)
    }

    @Test func quiesceClearsTheDurableOutbox() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let outbox = SpyLocationOutbox()
        let ingestor = Self.makeIngestor(
            store: store,
            source: source,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        await ingestor.start()

        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }
        #expect(await outbox.contents.count == 1)

        // A reset/erase teardown must wipe the durable backlog too, or it would
        // re-drain into the freshly erased store on the next launch.
        await ingestor.quiesce()
        #expect(await ingestor.retryQueueDepth == 0)
        #expect(await outbox.contents.isEmpty)
    }

    @Test func authorizationReflectsTheSource() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .whenInUse)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        #expect(await ingestor.authorizationStatus() == .whenInUse)
    }

    private func sample(at isoString: String) -> LocationSample {
        LocationSample(
            timestamp: iso(isoString),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ predicate: () async -> Bool,
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while await !predicate() {
            if ContinuousClock.now >= deadline { throw WaitTimeout() }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

private struct WaitTimeout: Error {}

private struct ToggleFailingStoreError: Error {}

/// `WhereStore` that lets a test toggle whether `add(sample:)` succeeds; every
/// other API forwards to a real in-memory `SwiftDataStore`.
private actor ToggleFailingStore: WhereStore {
    private let backing: SwiftDataStore
    private var shouldFail = false

    init(backing: SwiftDataStore) {
        self.backing = backing
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func perform<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
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

    func clearManualDay(_ date: Date) async throws {
        try await backing.clearManualDay(date)
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

private func iso(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string) ?? Date(timeIntervalSince1970: 0)
}
