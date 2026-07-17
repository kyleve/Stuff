import Foundation
import RegionKit

/// Type-erased entry point so a heterogeneous detector list runs uniformly.
public protocol DataIssueDetecting: Sendable {
    func detectAnyIssues(in input: DataIssueInput) -> [any DataIssue]
}

public protocol DataIssueDetector<Issue>: DataIssueDetecting where Issue: DataIssue {
    associatedtype Issue: DataIssue
    func detectIssues(in input: DataIssueInput) -> [Issue]
}

extension DataIssueDetector {
    public func detectAnyIssues(in input: DataIssueInput) -> [any DataIssue] {
        detectIssues(in: input).map(\.self)
    }
}

public struct DataIssueInput: Sendable {
    public let year: Int
    public let report: YearReport
    public let otherDayCoordinates: [CalendarDay: [Coordinate]]
    /// The year's passive GPS fixes, queryable per day, for a speed-based
    /// detector (`FlightDayDetector`) that needs per-fix timestamps the
    /// aggregated `report` has collapsed away. Lazy and memoized (see
    /// `DaySamples`), so a scan whose detectors never consult it does no
    /// grouping work.
    public let daySamples: DaySamples
    public let primaryRegions: [Region]
    public let attributor: any RegionAttributing
    public let driftThresholdMeters: Double
    public let calendar: Calendar
    public let now: Date

    public init(
        year: Int,
        report: YearReport,
        otherDayCoordinates: [CalendarDay: [Coordinate]],
        daySamples: DaySamples,
        primaryRegions: [Region],
        attributor: any RegionAttributing,
        driftThresholdMeters: Double,
        calendar: Calendar,
        now: Date,
    ) {
        self.year = year
        self.report = report
        self.otherDayCoordinates = otherDayCoordinates
        self.daySamples = daySamples
        self.primaryRegions = primaryRegions
        self.attributor = attributor
        self.driftThresholdMeters = driftThresholdMeters
        self.calendar = calendar
        self.now = now
    }
}
