import Foundation
import RegionKit

/// Reads the persisted year + dismissals, runs the pure detectors, and returns
/// the sorted, not-yet-dismissed issues — throttling repeat scans of the same
/// (year, threshold, calendar day) to once per `scanInterval` and serving the
/// cached result in between. The calendar day is part of the key because the
/// missing-days backlog cutoff (`MissingDays.backlogCutoff`) is day-relative, so
/// a midnight rollover must recompute even mid-throttle — the cache fully
/// describes when it's stale, so callers just keep asking with `force: false`.
/// An `actor` because it holds that cache; composes `ReportReader`.
public actor DataIssueScanner {
    private let reportReader: ReportReader
    private let attributor: any RegionAttributing
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let scanInterval: TimeInterval
    private let detectors: [any DataIssueDetecting]

    private struct CachedScan {
        let year: Int
        let driftThresholdMeters: Double
        /// Start-of-day of the `now` this scan ran against. The day-relative
        /// backlog cutoff is baked into `issues`, so a different day is a miss.
        let day: Date
        let at: Date
        let issues: [any DataIssue]
    }

    private var cache: CachedScan?

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
            BorderDriftDetector(),
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

    /// Throttled detection. Recomputes when `force`, when the cache is empty,
    /// when `(year, driftThresholdMeters)` differs from the cached run, when the
    /// calendar day has rolled over since it (the backlog cutoff is
    /// day-relative), or when the cached run is older than `scanInterval`;
    /// otherwise returns cached.
    public func issues(
        year: Int,
        primaryRegions: [Region],
        driftThresholdMeters: Double,
        force: Bool = false,
    ) async throws -> [any DataIssue] {
        let currentDate = now()
        let currentDay = calendar.startOfDay(for: currentDate)
        if !force,
           let cached = cache,
           cached.year == year,
           cached.driftThresholdMeters == driftThresholdMeters,
           cached.day == currentDay,
           currentDate.timeIntervalSince(cached.at) < scanInterval
        {
            return cached.issues
        }

        let report = try await reportReader.yearReport(for: year)
        let otherLocations = try await reportReader.locations(in: .other, year: year)
        let otherDayCoordinates = Dictionary(
            uniqueKeysWithValues: otherLocations.map { ($0.day, $0.points.map(\.coordinate)) },
        )
        let dismissed = try await reportReader.dismissedIssueIDs()
        let input = DataIssueInput(
            year: year,
            report: report,
            otherDayCoordinates: otherDayCoordinates,
            primaryRegions: primaryRegions,
            attributor: attributor,
            driftThresholdMeters: driftThresholdMeters,
            calendar: calendar,
            now: currentDate,
        )
        let sorted = Self.sortIssues(
            detectors
                .flatMap { $0.detectAnyIssues(in: input) }
                .filter { !dismissed.contains($0.id) },
        )
        cache = CachedScan(
            year: year,
            driftThresholdMeters: driftThresholdMeters,
            day: currentDay,
            at: currentDate,
            issues: sorted,
        )
        return sorted
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
