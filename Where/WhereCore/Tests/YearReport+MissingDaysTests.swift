import Foundation
import Testing
import WhereCore

struct YearReportMissingDaysTests {
    private let calendar = WhereCoreTestSupport.calendar()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
        ))!)
    }

    /// A current-year report surfaces the past gaps (Jan 1 through yesterday) and
    /// excludes today, which is still loggable.
    @Test func currentYearSurfacesPastGapsExcludingToday() {
        let now = day(2026, 1, 5)
        let report = YearReport(
            year: 2026,
            days: [
                DayPresence(date: day(2026, 1, 2), regions: [.california]),
                DayPresence(date: day(2026, 1, 4), regions: [.california]),
            ],
            totals: [.california: 2],
        )

        // Present: Jan 2 & Jan 4. Missing through Jan 4 (yesterday): Jan 1 & Jan 3.
        #expect(report.missingDayRanges(asOf: now, calendar: calendar).map(\.start) == [
            day(2026, 1, 1),
            day(2026, 1, 3),
        ])
        #expect(report.missingDayCount(asOf: now, calendar: calendar) == 2)
        #expect(report.missingDayKeys(asOf: now, calendar: calendar) == [
            day(2026, 1, 1),
            day(2026, 1, 3),
        ])
        // Today (Jan 5) is never surfaced — it can still be logged.
        #expect(!report.missingDayKeys(asOf: now, calendar: calendar).contains(day(2026, 1, 5)))
    }

    /// A past year can't gain today's coverage, so it has no missing days even
    /// with nothing logged.
    @Test func pastYearHasNoMissingDays() {
        let now = day(2026, 6, 15)
        let report = YearReport(year: 2025, days: [], totals: [:])

        #expect(!report.isCurrentYear(asOf: now, calendar: calendar))
        #expect(report.missingDayRanges(asOf: now, calendar: calendar).isEmpty)
        #expect(report.missingDayCount(asOf: now, calendar: calendar) == 0)
        #expect(report.missingDayKeys(asOf: now, calendar: calendar).isEmpty)
    }
}
