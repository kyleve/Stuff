import Foundation

/// Reads the persisted year + dismissals, runs the pure detectors, and returns
/// the sorted, not-yet-dismissed issues — throttling repeat scans of the same
/// (year, threshold) to once per `scanInterval` and serving the cached result
/// in between. An `actor` because it holds that cache; composes `ReportReader`.
public actor DataIssueScanner {
    private let reportReader: ReportReader
    private let attributor: RegionAttributor
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let scanInterval: TimeInterval
    private let detectors: [any DataIssueDetecting]

    private struct CachedScan {
        let year: Int
        let driftThresholdMeters: Double
        let at: Date
        let issues: [any DataIssue]
    }

    private var cache: CachedScan?

    public init(
        reportReader: ReportReader,
        attributor: RegionAttributor,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date = { Date() },
        scanInterval: TimeInterval = 3 * 60 * 60,
        detectors: [any DataIssueDetecting] = [
            MissingDaysDetector(),
            BorderDriftDetector(),
            AbruptLocationChangeDetector(),
        ],
    ) {
        self.reportReader = reportReader
        self.attributor = attributor
        self.calendar = calendar
        self.now = now
        self.scanInterval = scanInterval
        self.detectors = detectors
    }

    /// Throttled detection. Recomputes when `force`, when the cache is empty,
    /// when `(year, driftThresholdMeters)` differs from the cached run, or when
    /// the cached run is older than `scanInterval`; otherwise returns cached.
    public func issues(
        year: Int,
        primaryRegions: [Region],
        driftThresholdMeters: Double,
        force: Bool = false,
    ) async throws -> [any DataIssue] {
        if !force,
           let cached = cache,
           cached.year == year,
           cached.driftThresholdMeters == driftThresholdMeters,
           now().timeIntervalSince(cached.at) < scanInterval
        {
            return cached.issues
        }

        let report = try await reportReader.yearReport(for: year)
        let otherLocations = try await reportReader.locations(in: .other, year: year)
        let otherDayCoordinates = Dictionary(
            uniqueKeysWithValues: otherLocations.map { ($0.date, $0.coordinates) },
        )
        let dismissed = try await reportReader.dismissedIssueKeys()
        let input = DataIssueInput(
            year: year,
            report: report,
            otherDayCoordinates: otherDayCoordinates,
            primaryRegions: primaryRegions,
            attributor: attributor,
            driftThresholdMeters: driftThresholdMeters,
            calendar: calendar,
            now: now(),
        )
        let sorted = Self.sortIssues(
            detectors
                .flatMap { $0.detectAnyIssues(in: input) }
                .filter { !dismissed.contains($0.id.storageKey) },
        )
        cache = CachedScan(
            year: year,
            driftThresholdMeters: driftThresholdMeters,
            at: now(),
            issues: sorted,
        )
        return sorted
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
