import Foundation
import RegionKit

/// Publishes issues and informational GPS reviews from one evidence snapshot.
/// Cache invalidation has its own epoch so a suspended scan cannot republish
/// evidence that was invalidated while its reads were in flight.
public actor DataIssueScanner {
    private static let logger = WhereLog.reporting(DataIssueScannerLog.self)

    private let reportReader: ReportReader
    private let attributor: any RegionAttributing
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let scanInterval: TimeInterval
    private let detectors: [any DataIssueDetecting]

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
    private var invalidationRevision: UInt64 = 0

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
        invalidationTask = Task { [weak self] in
            for await _ in storeChanges {
                await self?.invalidate()
            }
        }
    }

    deinit {
        invalidationTask?.cancel()
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
                let input = DataIssueInput(
                    year: year,
                    report: reads.report,
                    otherDayCoordinates: reads.otherDayCoordinates,
                    daySamples: reads.daySamples,
                    primaryRegions: primaryRegions,
                    attributor: reads.attribution,
                    driftThresholdMeters: driftThresholdMeters,
                    calendar: calendar,
                    now: currentDate,
                )
                let reviews = Self.logger.measure(.assessGPS) {
                    SampleCorrectionAssessment(attributor: reads.attribution, calendar: calendar)
                        .reviews(
                            reads: reads,
                            primaryRegions: primaryRegions,
                            driftThresholdMeters: driftThresholdMeters,
                            now: currentDate,
                        )
                }
                let otherIssues = detectors.flatMap { detector in
                    Self.logger.measure(.detect(detector.detects)) {
                        detector.detectAnyIssues(in: input)
                    }
                }
                let flightDays = Set(reviews.filter { !$0.flights.isEmpty }.map(\.day.day))
                let unexplainedIssues = otherIssues.filter { issue in
                    // Flight reviews own these transitions before and after
                    // arrival, including their exact-sample correction. Do not
                    // also offer a whole-day travel correction for that flight.
                    guard case let .markTravelDay(earlier, later, _) = issue.resolution else {
                        return true
                    }
                    return !flightDays.contains(earlier.day) && !flightDays.contains(later.day)
                }
                let gpsIssues: [any DataIssue] = reviews.compactMap { review in
                    review.proposal.map { SampleCorrectionIssue(proposal: $0) }
                }
                let issues = Self.sortIssues((unexplainedIssues + gpsIssues).filter {
                    !reads.dismissedIssueIDs.contains($0.id)
                })
                let deadlines = reviews.flatMap(\.flights).flatMap { flight in
                    [
                        flight.nextReassessmentAt,
                        flight.lastObservationAt.addingTimeInterval(24 * 60 * 60),
                    ]
                    .compactMap(\.self).filter { $0 > currentDate }
                }
                return DataIssueScanResult(
                    revision: UUID(),
                    issues: issues,
                    reviews: reviews,
                    nextReassessmentAt: deadlines.min(),
                )
            }
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
    }

    private static func sortIssues(_ issues: [any DataIssue]) -> [any DataIssue] {
        issues.sorted { lhs, rhs in
            let lhsOrder = DataIssueCategory.allCases.firstIndex(of: lhs.category) ?? 0
            let rhsOrder = DataIssueCategory.allCases.firstIndex(of: rhs.category) ?? 0
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.sortKey < rhs.sortKey
        }
    }
}
