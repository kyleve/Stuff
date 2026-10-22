import Foundation
import RegionKit

/// A coherent, policy-filtered year snapshot for the optional Elsewhere projection.
/// Raw evidence revisions remain part of equality even when day totals do not change.
public struct ElsewhereInput: Hashable, Sendable {
    public let report: YearReport
    public let primaryRegions: Set<Region>
    public let history: LocationHistoryProjection
    public let manualDays: [DayPresence]
    public let calendar: Calendar

    public init(
        report: YearReport,
        primaryRegions: Set<Region>,
        history: LocationHistoryProjection,
        manualDays: [DayPresence],
        calendar: Calendar,
    ) {
        self.report = report
        self.primaryRegions = primaryRegions
        self.history = history
        self.manualDays = manualDays
        self.calendar = calendar
    }

    /// Eligibility needs no catalog geometry or network lookup.
    public var hasVisits: Bool {
        report.totals.contains { region, count in
            count > 0 && !primaryRegions.contains(region)
        }
    }
}
