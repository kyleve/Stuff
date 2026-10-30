import Foundation
import RegionKit

/// A single-read year snapshot with configured primaries, aggregate day counts,
/// recorded fixes, and the evidence needed to resolve Elsewhere.
/// Keeping these projections together guarantees they describe the same store
/// contents, even when a new fix leaves the aggregate ``YearReport`` unchanged.
public struct YearReportDetails: Equatable, Sendable {
    public var report: YearReport {
        elsewhereInput.report
    }

    public var primaryRegions: Set<Region> {
        elsewhereInput.primaryRegions
    }

    public let elsewhereInput: ElsewhereInput
    public let primaryRegionLocations: [Region: [RegionDayLocations]]

    public init(
        elsewhereInput: ElsewhereInput,
        primaryRegionLocations: [Region: [RegionDayLocations]],
    ) {
        self.elsewhereInput = elsewhereInput
        self.primaryRegionLocations = primaryRegionLocations
    }
}

#if DEBUG
    extension YearReportDetails {
        /// Synchronous manual-history fixture, using the same resolver input as production.
        @_spi(Testing)
        public init(
            primaryRegions: Set<Region>,
            report: YearReport,
            primaryRegionLocations: [Region: [RegionDayLocations]],
        ) {
            self.init(
                elsewhereInput: ElsewhereInput(
                    report: report,
                    primaryRegions: primaryRegions,
                    history: LocationHistoryProjection(samples: [], revisions: []),
                    manualDays: report.days,
                    calendar: Calendar(identifier: .gregorian),
                ),
                primaryRegionLocations: primaryRegionLocations,
            )
        }
    }
#endif
