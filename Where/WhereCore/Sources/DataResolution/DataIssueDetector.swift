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
    /// Passive GPS fixes for the year keyed by `CalendarDay`, each day's samples
    /// sorted ascending by timestamp. Only `.gpsVisit` / `.gpsSignificantChange`
    /// sources are included — manual and evidence-implied samples carry
    /// user-asserted timestamps that would produce meaningless speeds — so a
    /// speed-based detector (`FlightDayDetector`) can walk consecutive fixes.
    /// Unlike `report` / `otherDayCoordinates` these retain per-fix timestamps.
    public let daySamples: [CalendarDay: [LocationSample]]
    public let primaryRegions: [Region]
    public let attributor: any RegionAttributing
    public let driftThresholdMeters: Double
    public let calendar: Calendar
    public let now: Date

    public init(
        year: Int,
        report: YearReport,
        otherDayCoordinates: [CalendarDay: [Coordinate]],
        daySamples: [CalendarDay: [LocationSample]],
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
