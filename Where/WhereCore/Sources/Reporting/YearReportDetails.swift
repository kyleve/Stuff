import RegionKit

/// A single-read year snapshot for presentation surfaces that need both the
/// aggregate report and the recorded fixes behind its primary regions.
/// Keeping both projections together guarantees they describe the same store
/// contents, even when a new fix leaves the aggregate ``YearReport`` unchanged.
public struct YearReportDetails: Equatable, Sendable {
    public let report: YearReport
    public let primaryRegionLocations: [Region: [RegionDayLocations]]

    public init(
        report: YearReport,
        primaryRegionLocations: [Region: [RegionDayLocations]],
    ) {
        self.report = report
        self.primaryRegionLocations = primaryRegionLocations
    }
}
