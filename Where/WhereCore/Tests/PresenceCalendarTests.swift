import Foundation
import Testing
@testable import WhereCore

struct PresenceCalendarTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    private func report(_ days: [DayPresence], year: Int = 2026) -> YearReport {
        YearReport(year: year, days: days, totals: [:])
    }

    private func referenceDate(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        day(year, month, dayOfMonth)
    }

    @Test func monthsFromReportReturnsTwelveMonthsInOrder() {
        let months = PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        #expect(months.count == 12)
        #expect(months.map(\.month) == Array(1 ... 12))
        #expect(months.allSatisfy { $0.year == 2026 })
    }

    @Test func monthCountFollowsCalendarYearRange() {
        guard
            let yearStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)),
            let expected = calendar.range(of: .month, in: .year, for: yearStart)?.count
        else {
            Issue.record("Could not resolve month range for 2026")
            return
        }
        let months = PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        #expect(months.count == expected)
    }

    @Test func leadingBlankCountForJanuary2026() {
        // Jan 1 2026 is a Thursday; with Sunday-first, that is 4 leading blanks.
        let months = PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let january = months[0]
        #expect(january.month == 1)
        #expect(january.leadingBlankCount == 4)
    }

    @Test func weekdayCountMatchesCalendarMaximumRange() {
        let months = PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let expected = calendar.maximumRange(of: .weekday)?.count ?? 7
        #expect(months.allSatisfy { $0.weekdayCount == expected })
        #expect(months[0].weekdaySymbols.count == expected)
    }

    @Test func dayRegionsAreSortedByRegionAllCasesOrder() {
        let days = [
            DayPresence(date: day(2026, 3, 15), regions: [.newYork, .california]),
        ]
        let months = PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let marchDay = months[2].days.first { $0.dayOfMonth == 15 }
        #expect(marchDay?.regions == [.california, .newYork])
    }

    @Test func dayCountMatchesCalendarRange() {
        let months = PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let february = months[1]
        #expect(february.days.count == 28)
    }

    @Test func dayWithNoPresenceHasEmptyRegions() {
        let months = PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let januaryFirst = months[0].days[0]
        #expect(januaryFirst.dayOfMonth == 1)
        #expect(januaryFirst.regions.isEmpty)
    }

    @Test func dayWithPresenceIncludesMatchingRegions() {
        let days = [
            DayPresence(date: day(2026, 6, 10), regions: [.canada, .europeanUnion]),
        ]
        let months = PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let juneDay = months[5].days.first { $0.dayOfMonth == 10 }
        #expect(juneDay?.regions == [.canada, .europeanUnion])
    }

    @Test func marksReferenceDateAsToday() {
        let reference = referenceDate(2026, 3, 4)
        let months = PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: reference,
        )
        let marchDay = months[2].days.first { $0.dayOfMonth == 4 }
        #expect(marchDay?.isToday == true)
        #expect(months[2].isCurrentMonth == true)
    }

    @Test func marksMissingDatesAsNeedingAttention() {
        let missing = day(2026, 2, 5)
        let months = PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            missingDates: [missing],
        )
        let februaryDay = months[1].days.first { $0.dayOfMonth == 5 }
        #expect(februaryDay?.needsAttention == true)
    }

    @Test func yearReportCalendarMonthsMatchesPresenceCalendar() {
        let report = report([
            DayPresence(date: day(2026, 1, 1), regions: [.california]),
        ])
        let reference = referenceDate(2026, 1, 1)
        #expect(report.calendarMonths(calendar: calendar, referenceDate: reference)
            == PresenceCalendar.months(from: report, calendar: calendar, referenceDate: reference))
    }
}
