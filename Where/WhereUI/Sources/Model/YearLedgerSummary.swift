import RegionKit
import WhereCore

/// Honest, presentation-only figures for the annual ledger cover.
///
/// Every field is derived from an already-loaded `YearReport`; the cover never
/// guesses at missing data or substitutes a fabricated zero for load failure.
struct YearLedgerSummary: Equatable {
    let recordedDayCount: Int
    let namedRegionCount: Int
    let elsewhereDayCount: Int
    let leadingRegion: RegionDays?
    let latestRecordedDay: CalendarDay?

    var includesElsewhere: Bool {
        elsewhereDayCount > 0
    }

    init(report: YearReport) {
        let rankedNamedRegions = RegionRanking.ranked(report: report)
            .filter { $0.region != .other }
        recordedDayCount = report.days.count
        namedRegionCount = rankedNamedRegions.count
        elsewhereDayCount = report.totals[.other] ?? 0
        leadingRegion = rankedNamedRegions.first
        latestRecordedDay = report.days.last?.day
    }
}
