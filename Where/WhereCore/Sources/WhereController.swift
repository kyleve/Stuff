import Foundation
import os

/// Top-level API for the Where feature. Composes a `WhereStore`
/// (persistence) and a `LocationSource` (GPS) behind a small,
/// testable surface.
///
/// - GPS sampling is opt-in: callers invoke `startGPS()` once the user grants
///   authorization. Ingestion runs in an unstructured `Task` owned by the
///   actor; `stopGPS()` pauses the underlying monitoring while leaving the
///   task alive (so the stream can be resumed), and `deinit` cancels it.
/// - Retroactive entry uses `addManualSample(_:)` (a single coordinate) or
///   `addManualDay(date:regions:)` (an authoritative day overlay that unions
///   with whatever GPS produced for that day).
/// - `yearReport(for:)` reads everything in the requested calendar year via
///   the injected `DayAggregator` and returns a snapshot-stable `YearReport`.
public actor WhereController {
    private let store: any WhereStore
    private let locationSource: any LocationSource
    private let attributor: RegionAttributor
    private let aggregator: DayAggregator

    private var ingestTask: Task<Void, Never>?

    /// Whether the underlying location monitoring is currently active. Tracked
    /// separately from `ingestTask` because the ingestion task outlives a
    /// `stopGPS()` pause (see `startGPS()` for why).
    private var isMonitoring = false

    /// Samples whose persist call failed (e.g. transient SwiftData / CloudKit
    /// error). Drained before each new GPS save and on the next `startGPS()`
    /// so a brief I/O outage doesn't silently drop measurements.
    private var retryQueue: [LocationSample] = []

    /// Hard cap on the retry queue. Once reached, the oldest pending sample
    /// is dropped to make room for the newest. Sized to ~12 hours of
    /// significant-change/Visits ingestion (which fires on the order of
    /// minutes, not seconds), so reaching the cap means something is very
    /// wrong with persistence and we'd rather keep recent data than ancient.
    private static let retryQueueCapacity = 1000

    private static let logger = Logger(subsystem: "com.stuff.where", category: "WhereController")

    public init(
        store: any WhereStore,
        locationSource: any LocationSource,
        attributor: RegionAttributor = .shared,
        aggregator: DayAggregator = DayAggregator(),
    ) {
        self.store = store
        self.locationSource = locationSource
        self.attributor = attributor
        self.aggregator = aggregator
    }

    deinit {
        ingestTask?.cancel()
    }

    // MARK: - Ingestion

    public func ingest(_ sample: LocationSample) async throws {
        try await store.perform { try await store.add(sample: sample) }
    }

    // MARK: - Retroactive entry

    public func addManualSample(_ sample: LocationSample) async throws {
        try await store.perform { try await store.add(sample: sample) }
    }

    public func addManualDay(date: Date, regions: Set<Region>) async throws {
        let key = aggregator.calendar.startOfDay(for: date)
        let presence = DayPresence(date: key, regions: regions)
        try await store.perform { try await store.setManualDay(presence) }
    }

    /// Assert `regions` for every calendar day in the inclusive range
    /// `start...end` (handy for backfilling a trip). Both bounds are
    /// normalized to start-of-day in the aggregator's calendar, and the
    /// whole range is written inside a single `perform` transaction so the
    /// backfill commits (or rolls back) atomically. A `start` later than
    /// `end` is treated as an empty range and writes nothing.
    public func addManualDays(
        from start: Date,
        through end: Date,
        regions: Set<Region>,
    ) async throws {
        // `calendarDays` returns an immutable array, so the `@Sendable`
        // transaction body captures a `let` rather than a mutable cursor
        // across the concurrency boundary.
        let dayKeys = start.calendarDays(through: end, in: aggregator.calendar)
        guard !dayKeys.isEmpty else { return }
        try await store.perform {
            for day in dayKeys {
                try await store.setManualDay(DayPresence(date: day, regions: regions))
            }
        }
    }

    // MARK: - Evidence

    public func addEvidence(_ evidence: Evidence, blob: Data? = nil) async throws {
        try await store.perform { try await store.write(evidence: evidence, blob: blob) }
    }

    public func evidence(for year: Int) async throws -> [Evidence] {
        try await store.evidence(in: aggregator.yearInterval(year: year))
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        try await store.evidenceBlob(for: id)
    }

    // MARK: - Reporting

    public func yearReport(for year: Int) async throws -> YearReport {
        let interval = aggregator.yearInterval(year: year)
        let samples = try await store.samples(in: interval)
        let manuals = try await store.manualDays(in: interval)
        return aggregator.report(
            for: year,
            samples: samples,
            manualDays: manuals,
            attributor: attributor,
        )
    }

    public func clearYear(_ year: Int) async throws {
        let interval = aggregator.yearInterval(year: year)
        try await store.perform { try await store.clear(in: interval) }
    }

    // MARK: - GPS lifecycle

    /// Begin (or resume) GPS ingestion. Idempotent: a second call while
    /// monitoring is already active is a no-op, so the lifecycle is safe to
    /// drive from multiple call sites (e.g. scene activation + a manual
    /// toggle).
    ///
    /// The task that drains `locationSource.sampleStream` is created once and
    /// then kept alive for the controller's lifetime; `stopGPS()` only pauses
    /// the underlying monitoring. Cancelling that task would terminate the
    /// single-consumer `AsyncStream`, so a later `startGPS()` would iterate an
    /// already-finished stream and silently drop every subsequent sample.
    public func startGPS() async {
        guard !isMonitoring else { return }
        isMonitoring = true
        await locationSource.start()
        // Flush anything that failed to persist before this session
        // started, before we (re)attach the stream consumer.
        await drainRetryQueue()
        guard ingestTask == nil else { return }
        let stream = locationSource.sampleStream
        ingestTask = Task { [weak self] in
            for await sample in stream {
                if Task.isCancelled { break }
                guard let self else { break }
                await processIngestedSample(sample)
            }
        }
    }

    /// Persist one GPS-sourced sample, falling back to the retry queue
    /// on failure. Drains any backlog first so a single transient
    /// outage doesn't permanently reorder samples on disk.
    private func processIngestedSample(_ sample: LocationSample) async {
        await drainRetryQueue()
        do {
            try await store.perform { try await store.add(sample: sample) }
        } catch {
            // Persistence failures (SwiftData save, CloudKit, etc.)
            // are surfaced via `os.Logger` instead of being silently
            // dropped. The stream keeps running so a transient error
            // doesn't stop tracking, and the sample is queued for
            // retry on the next save attempt.
            Self.logger.error(
                "Failed to persist GPS sample \(sample.id, privacy: .public): \(error.localizedDescription, privacy: .public)",
            )
            enqueueForRetry(sample)
        }
    }

    private func enqueueForRetry(_ sample: LocationSample) {
        if retryQueue.count >= Self.retryQueueCapacity {
            retryQueue.removeFirst()
        }
        retryQueue.append(sample)
    }

    /// Try to flush every queued sample exactly once. Anything that
    /// still fails is re-queued at the tail; the next call gets the
    /// chance to retry it.
    private func drainRetryQueue() async {
        guard !retryQueue.isEmpty else { return }
        let pending = retryQueue
        retryQueue.removeAll(keepingCapacity: true)
        for sample in pending {
            do {
                try await store.perform { try await store.add(sample: sample) }
            } catch {
                Self.logger.error(
                    "Retry still failing for GPS sample \(sample.id, privacy: .public): \(error.localizedDescription, privacy: .public)",
                )
                enqueueForRetry(sample)
            }
        }
    }

    /// Number of samples currently waiting to be re-persisted. Exposed
    /// for tests; production callers should treat this as opaque.
    public var retryQueueDepth: Int {
        retryQueue.count
    }

    /// Pause GPS ingestion by stopping the underlying location monitoring.
    /// Idempotent and safe to call from teardown paths that may run before
    /// any `startGPS()` (e.g. scene background, error recovery). The
    /// ingestion task is intentionally left running (see `startGPS()`); it
    /// simply idles until monitoring resumes. The task is torn down on
    /// `deinit`.
    public func stopGPS() async {
        guard isMonitoring else { return }
        isMonitoring = false
        await locationSource.stop()
    }

    public func requestLocationPermission() async throws {
        try await locationSource.requestPermission()
    }

    /// The current location authorization status.
    public func authorizationStatus() async -> LocationAuthorizationStatus {
        await locationSource.currentAuthorization()
    }

    /// Live stream of authorization-status changes (system prompt results and
    /// Settings-app changes). Subscribe once and iterate.
    public func authorizationUpdates() -> AsyncStream<LocationAuthorizationStatus> {
        locationSource.authorizationUpdates
    }

    /// Whether GPS monitoring is currently active. Exposed so the view-model
    /// can reconcile its tracking flag with reality after launch.
    public var isTrackingActive: Bool {
        isMonitoring
    }
}
