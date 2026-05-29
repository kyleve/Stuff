import Foundation
import os

/// Top-level API for the Where feature. Composes a `WhereStore`
/// (persistence) and a `LocationSource` (GPS) behind a small,
/// testable surface.
///
/// - GPS sampling is opt-in: callers invoke `startGPS()` once the user grants
///   authorization. Ingestion runs in an unstructured `Task` owned by the
///   actor so it can be cancelled by `stopGPS()` / `deinit`.
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
        let calendar = aggregator.calendar
        let last = calendar.startOfDay(for: end)
        // Enumerate the day keys up front into an immutable array so the
        // `@Sendable` transaction body captures a `let`, not a mutable
        // cursor, across the concurrency boundary.
        let dayKeys: [Date] = {
            var keys: [Date] = []
            var cursor = calendar.startOfDay(for: start)
            while cursor <= last {
                keys.append(cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = calendar.startOfDay(for: next)
            }
            return keys
        }()
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

    public func startGPS() async {
        // Idempotent: a second call while a stream is already attached
        // is a no-op so the GPS lifecycle is safe to drive from
        // multiple call sites (e.g. scene activation + manual button).
        guard ingestTask == nil else { return }
        await locationSource.start()
        // Flush anything that failed to persist before this session
        // started, before we attach the new stream.
        await drainRetryQueue()
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

    public func stopGPS() async {
        // Idempotent: cheap no-op when nothing is running so this is
        // safe to call from teardown paths that may run before any
        // `startGPS()` (e.g. scene background, error recovery).
        guard let task = ingestTask else { return }
        task.cancel()
        ingestTask = nil
        await locationSource.stop()
    }

    public func requestLocationPermission() async throws {
        try await locationSource.requestPermission()
    }
}
