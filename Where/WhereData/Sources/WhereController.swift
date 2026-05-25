import Foundation
import os
import WhereCore

/// Top-level API for `WhereData`. Composes a `WhereStore` (persistence) and
/// a `LocationSource` (GPS) behind a small, testable surface.
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

    private static let logger = Logger(subsystem: "com.stuff.where", category: "WhereController")

    public init(
        store: any WhereStore,
        locationSource: any LocationSource,
        attributor: RegionAttributor = .bundled,
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
        try await store.addSample(sample)
    }

    // MARK: - Retroactive entry

    public func addManualSample(_ sample: LocationSample) async throws {
        try await store.addSample(sample)
    }

    public func addManualDay(date: Date, regions: Set<Region>) async throws {
        let key = aggregator.calendar.startOfDay(for: date)
        try await store.setManualDay(DayPresence(date: key, regions: regions))
    }

    // MARK: - Evidence

    public func addEvidence(_ evidence: Evidence, blob: Data? = nil) async throws {
        try await store.addEvidence(evidence, blob: blob)
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
        try await store.clear(in: aggregator.yearInterval(year: year))
    }

    // MARK: - GPS lifecycle

    public func startGPS() async {
        await locationSource.start()
        ingestTask?.cancel()
        let stream = locationSource.sampleStream
        let store = store
        let logger = Self.logger
        ingestTask = Task {
            for await sample in stream {
                if Task.isCancelled { break }
                do {
                    try await store.addSample(sample)
                } catch {
                    // Persistence failures (SwiftData save, CloudKit, etc.)
                    // are surfaced via `os.Logger` instead of being silently
                    // dropped. The stream keeps running so a transient error
                    // doesn't stop tracking, but the failure is visible in
                    // Console and `os_log` traces.
                    logger
                        .error(
                            "Failed to persist GPS sample \(sample.id, privacy: .public): \(error.localizedDescription, privacy: .public)",
                        )
                }
            }
        }
    }

    public func stopGPS() async {
        ingestTask?.cancel()
        ingestTask = nil
        await locationSource.stop()
    }

    public func requestAlwaysAuthorization() async {
        await locationSource.requestAlwaysAuthorization()
    }
}
