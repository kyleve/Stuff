import RegionKit
import WhereCore

extension WidgetSnapshot {
    /// The snapshot's totals ranked exactly like the app's tabs
    /// (`RegionRanking.ranked`: day count descending, declaration-order
    /// ties), capped to what the widget family can fit.
    func rankedTotals(maxRows: Int) -> [RegionDays] {
        let report = YearReport(year: year, days: [], totals: totals)
        return Array(RegionRanking.ranked(report: report).prefix(max(0, maxRows)))
    }

    /// Today's regions in `Region.allCases` declaration order so widget
    /// layouts are stable between timeline reloads.
    var orderedDayRegions: [Region] {
        Region.allCases.filter { dayRegions.contains($0) }
    }
}
