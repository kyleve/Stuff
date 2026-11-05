import Foundation
import RegionKit

/// Publishes issues and informational GPS reviews from one evidence snapshot.
/// Cache invalidation has its own epoch so a suspended scan cannot republish
/// evidence that was invalidated while its reads were in flight.
public actor DataIssueScanner {
    static let logger = WhereLog.reporting(DataIssueScannerLog.self)

    let reportReader: ReportReader
    let attributor: any RegionAttributing
    let calendar: Calendar
    let now: @Sendable () -> Date
    let scanInterval: TimeInterval
    let detectors: [any DataIssueDetecting]
    let recordingReviewScopeID = RecordingReviewSnapshot.ScopeID(rawValue: UUID())

    #if DEBUG
        private var beforeRecordingReviewPublication: (@Sendable () async -> Void)?
        var beforeHistoricalPublication: (@Sendable () async -> Void)?

        @_spi(Testing) public func setBeforeRecordingReviewPublicationForTesting(
            _ operation: @escaping @Sendable () async -> Void,
        ) {
            beforeRecordingReviewPublication = operation
        }
    #endif

    private struct CachedScan {
        let year: Int
        let primaryRegions: [Region]
        let trackedRegions: [Region]
        let driftThresholdMeters: Double
        /// Start-of-day of the `now` this scan ran against. The day-relative
        /// backlog cutoff is baked into `issues`, so a different day is a miss.
        let day: Date
        let at: Date
        let result: DataIssueScanResult
    }

    private var cache: CachedScan?
    var historicalCache: CachedHistoricalScan?
    /// Zero identifies the initial epoch; scans compare only equality. Change
    /// it even when the cache is empty so suspended scans detect invalidation.
    var invalidationRevision: UInt64

    /// Drops the cache whenever the store reports a committed change. Lets the
    /// cache stay honest for `force: false` readers even when no session is
    /// alive to force a rescan (e.g. a headless background GPS ingest).
    ///
    /// `nonisolated(unsafe)` because it's assigned once in the (nonisolated)
    /// initializer and only read by `deinit` — there is no concurrent access to
    /// guard.
    private nonisolated(unsafe) var invalidationTask: Task<Void, Never>?

    public init(
        reportReader: ReportReader,
        attributor: any RegionAttributing,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date = { Date() },
        scanInterval: TimeInterval = 3 * 60 * 60,
        detectors: [any DataIssueDetecting] = [
            MissingDaysDetector(),
            AbruptLocationChangeDetector(),
        ],
        // Defaults to an already-finished stream — *not* `AsyncStream { _ in }`,
        // which never yields or finishes and so would park the observation task
        // below forever — so callers that don't wire a store (previews, unit
        // tests) let that task complete immediately instead.
        storeChanges: AsyncStream<Void> = AsyncStream { $0.finish() },
    ) {
        self.reportReader = reportReader
        self.attributor = attributor
        self.calendar = calendar
        self.now = now
        self.scanInterval = scanInterval
        self.detectors = detectors
        invalidationRevision = 0
        invalidationTask = Task { [weak self] in
            for await _ in storeChanges {
                await self?.invalidate()
            }
        }
    }

    deinit {
        invalidationTask?.cancel()
    }

    /// Fresh absolute-period assessment, with bounded adjacent context for review. The queue's
    /// original logical query remains navigation context, never a filter on new rival evidence.
    public func recordingReview(periods: [RecordingPeriod]) async throws
        -> RecordingReviewSnapshot
    {
        while true {
            try Task.checkCancellation()
            let revision = invalidationRevision
            let result = try await reportReader.recordingReview(
                periods: periods,
                scopeID: recordingReviewScopeID,
            )
            #if DEBUG
                await beforeRecordingReviewPublication?()
            #endif
            try Task.checkCancellation()
            guard revision == invalidationRevision else { continue }
            return result
        }
    }

    /// Failure leaves the queue intact. Its owner keeps failed or skipped work pending and uses
    /// the guarded choice coordinator to save only the periods in the returned review item.
    public func reassess(_ queue: RecordingReviewQueue) async throws
        -> [RecordingReviewQueue.Item]
    {
        try queue.requireScope(recordingReviewScopeID)
        return try await queue.remaining(in: recordingReview(periods: queue.originalPeriods))
    }

    public func issues(
        year: Int,
        primaryRegions: [Region],
        driftThresholdMeters: Double,
        force: Bool = false,
    ) async throws -> [any DataIssue] {
        try await scan(
            year: year,
            primaryRegions: primaryRegions,
            driftThresholdMeters: driftThresholdMeters,
            force: force,
        ).issues
    }

    /// A cache miss builds a complete replacement publication. Overlapping
    /// misses may recompute independently; each returns its own complete result.
    public func scan(
        year: Int,
        primaryRegions: [Region],
        driftThresholdMeters: Double,
        force: Bool,
    ) async throws -> DataIssueScanResult {
        while true {
            try Task.checkCancellation()
            let currentDate = now()
            let currentDay = calendar.startOfDay(for: currentDate)
            let trackedRegions = attributor.loadedRegions
            if !force, let cached = cache,
               cached.year == year,
               cached.primaryRegions == primaryRegions,
               cached.trackedRegions == trackedRegions,
               cached.driftThresholdMeters == driftThresholdMeters,
               cached.day == currentDay,
               currentDate.timeIntervalSince(cached.at) < scanInterval,
               cached.result.nextReassessmentAt.map({ currentDate < $0 }) ?? true
            {
                return cached.result
            }
            let revision = invalidationRevision
            let result = try await Self.logger.measure(.scan, budget: .seconds(3)) {
                let reads = try await reportReader.dataIssueReads(for: year)
                return try DataIssueAssessment(calendar: calendar, detectors: detectors).scan(
                    reads: reads,
                    driftThresholdMeters: driftThresholdMeters,
                    now: currentDate,
                )
            }
            try Task.checkCancellation()
            guard revision == invalidationRevision,
                  trackedRegions == attributor.loadedRegions
            else {
                continue
            }
            cache = CachedScan(
                year: year,
                primaryRegions: primaryRegions,
                trackedRegions: trackedRegions,
                driftThresholdMeters: driftThresholdMeters,
                day: currentDay,
                at: currentDate,
                result: result,
            )
            return result
        }
    }

    /// Count of unresolved issues for `year`, for headless callers (the app-icon
    /// badge, the issue-alert notification) that don't have the UI's
    /// `RegionRanking` on hand. Derives `primaryRegions` through the shared
    /// `Region.primaryRegions` helper — the *same* definition `RegionRanking`
    /// builds the Primary/Elsewhere split from, so the "primary" rule lives in
    /// one place and this count can't disagree with what the Resolve tab shows
    /// (no ranking logic is duplicated here). This reads the report once to rank
    /// regions and `issues(...)` reads it again on a cache miss, so callers that
    /// already hold a report (the hot badge path in `ReminderReconciler`) should
    /// call `issues(...)` with `Region.primaryRegions(...)` directly to avoid the
    /// second read; this convenience is for the cold notification path.
    public func currentIssueCount(
        year: Int,
        driftThresholdMeters: Double,
        force: Bool = false,
    ) async throws -> Int {
        let report = try await reportReader.yearReport(for: year)
        return try await issues(
            year: year,
            primaryRegions: Region.primaryRegions(in: report.totals),
            driftThresholdMeters: driftThresholdMeters,
            force: force,
        ).count
    }

    /// Drop the cache so the next `issues(...)` recomputes regardless of throttle.
    public func invalidate() {
        invalidationRevision &+= 1
        cache = nil
        historicalCache = nil
    }
}
