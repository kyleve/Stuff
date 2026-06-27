import Foundation

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
    public let otherDayCoordinates: [Date: [Coordinate]]
    public let primaryRegions: [Region]
    public let attributor: RegionAttributor
    public let driftThresholdMeters: Double
    public let calendar: Calendar
    public let now: Date

    public init(
        year: Int,
        report: YearReport,
        otherDayCoordinates: [Date: [Coordinate]],
        primaryRegions: [Region],
        attributor: RegionAttributor,
        driftThresholdMeters: Double,
        calendar: Calendar,
        now: Date,
    ) {
        self.year = year
        self.report = report
        self.otherDayCoordinates = otherDayCoordinates
        self.primaryRegions = primaryRegions
        self.attributor = attributor
        self.driftThresholdMeters = driftThresholdMeters
        self.calendar = calendar
        self.now = now
    }
}
