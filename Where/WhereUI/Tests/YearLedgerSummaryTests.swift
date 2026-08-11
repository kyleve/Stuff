import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct YearLedgerSummaryTests {
    @Test func derivesFiguresFromTheLoadedReport() {
        let days = [
            DayPresence(
                day: CalendarDay(year: 2026, month: 1, day: 4),
                regions: [.california],
            ),
            DayPresence(
                day: CalendarDay(year: 2026, month: 5, day: 19),
                regions: [.california, .newYork],
            ),
            DayPresence(
                day: CalendarDay(year: 2026, month: 8, day: 2),
                regions: [.other],
            ),
        ]
        let report = YearReport(
            year: 2026,
            days: days,
            totals: [.california: 2, .newYork: 1, .other: 1],
        )

        let summary = YearLedgerSummary(report: report)

        #expect(summary.recordedDayCount == 3)
        #expect(summary.namedRegionCount == 2)
        #expect(summary.elsewhereDayCount == 1)
        #expect(summary.includesElsewhere)
        #expect(summary.leadingRegion == RegionDays(region: .california, days: 2))
        #expect(summary.latestRecordedDay == CalendarDay(year: 2026, month: 8, day: 2))
    }

    @Test func emptyReportRemainsExplicitlyEmpty() {
        let summary = YearLedgerSummary(report: YearReport(year: 2026, days: [], totals: [:]))

        #expect(summary.recordedDayCount == 0)
        #expect(summary.namedRegionCount == 0)
        #expect(summary.elsewhereDayCount == 0)
        #expect(summary.includesElsewhere == false)
        #expect(summary.leadingRegion == nil)
        #expect(summary.latestRecordedDay == nil)
    }

    @Test func elsewhereDoesNotBecomeALeadingNamedRegion() {
        let report = YearReport(
            year: 2026,
            days: [
                DayPresence(
                    day: CalendarDay(year: 2026, month: 2, day: 1),
                    regions: [.other],
                ),
            ],
            totals: [.other: 1],
        )

        let summary = YearLedgerSummary(report: report)

        #expect(summary.namedRegionCount == 0)
        #expect(summary.elsewhereDayCount == 1)
        #expect(summary.includesElsewhere)
        #expect(summary.leadingRegion == nil)
    }
}
