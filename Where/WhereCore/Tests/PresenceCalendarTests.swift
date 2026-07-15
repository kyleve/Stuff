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

    @Test func monthsFromReportReturnsTwelveMonthsInOrder() throws {
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        #expect(months.count == 12)
        #expect(months.map(\.month) == Array(1 ... 12))
        #expect(months.allSatisfy { $0.year == 2026 })
    }

    @Test func monthCountFollowsCalendarYearRange() throws {
        guard
            let yearStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)),
            let expected = calendar.range(of: .month, in: .year, for: yearStart)?.count
        else {
            Issue.record("Could not resolve month range for 2026")
            return
        }
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        #expect(months.count == expected)
    }

    @Test func leadingBlankCountForJanuary2026() throws {
        // Jan 1 2026 is a Thursday; with Sunday-first, that is 4 leading blanks.
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let january = months[0]
        #expect(january.month == 1)
        #expect(january.leadingBlankCount == 4)
    }

    @Test func weekdayCountMatchesCalendarMaximumRange() throws {
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        guard let expected = calendar.maximumRange(of: .weekday)?.count else {
            Issue.record("Could not resolve weekday range")
            return
        }
        #expect(months.allSatisfy { $0.weekdayCount == expected })
        #expect(months[0].weekdaySymbols.count == expected)
    }

    @Test func dayRegionsAreSortedByRegionAllCasesOrder() throws {
        let days = [
            DayPresence(date: day(2026, 3, 15), regions: [.newYork, .california]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let marchDay = months[2].days.first { $0.dayOfMonth == 15 }
        #expect(marchDay?.regions == [.california, .newYork])
    }

    @Test func dayCountMatchesCalendarRange() throws {
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let february = months[1]
        #expect(february.days.count == 28)
    }

    @Test func dayWithNoPresenceHasEmptyRegions() throws {
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let januaryFirst = months[0].days[0]
        #expect(januaryFirst.dayOfMonth == 1)
        #expect(januaryFirst.regions.isEmpty)
    }

    @Test func dayWithPresenceIncludesMatchingRegions() throws {
        let days = [
            DayPresence(date: day(2026, 6, 10), regions: [.canada, .europeanUnion]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let juneDay = months[5].days.first { $0.dayOfMonth == 10 }
        #expect(juneDay?.regions == [.canada, .europeanUnion])
    }

    @Test func marksReferenceDateAsToday() throws {
        let reference = referenceDate(2026, 3, 4)
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: reference,
        )
        let marchDay = months[2].days.first { $0.dayOfMonth == 4 }
        #expect(marchDay?.isToday == true)
        #expect(months[2].isCurrentMonth == true)
    }

    @Test func marksMissingDatesAsNeedingAttention() throws {
        let missing = day(2026, 2, 5)
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            missingDates: [missing],
        )
        let februaryDay = months[1].days.first { $0.dayOfMonth == 5 }
        #expect(februaryDay?.needsAttention == true)
    }

    @Test func yearReportCalendarMonthsMatchesPresenceCalendar() throws {
        let report = report([
            DayPresence(date: day(2026, 1, 1), regions: [.california]),
        ])
        let reference = referenceDate(2026, 1, 1)
        let fromReport = try report.calendarMonths(calendar: calendar, referenceDate: reference)
        let fromPresence = try PresenceCalendar.months(
            from: report,
            calendar: calendar,
            referenceDate: reference,
        )
        #expect(fromReport == fromPresence)
    }

    @Test func focusedRegionKeepsOnlyThatRegionsDots() throws {
        let days = [
            DayPresence(date: day(2026, 6, 1), regions: [.california, .newYork]),
            DayPresence(date: day(2026, 6, 2), regions: [.newYork]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            focusedRegion: .california,
        )
        let june = months[5]
        let mixedDay = june.days.first { $0.dayOfMonth == 1 }
        let otherRegionDay = june.days.first { $0.dayOfMonth == 2 }
        #expect(mixedDay?.regions == [.california])
        // A day where the focused region wasn't present shows no dots.
        #expect(otherRegionDay?.regions == [])
    }

    @Test func unfocusedMonthShowsEveryRegionDot() throws {
        let days = [
            DayPresence(date: day(2026, 6, 1), regions: [.california, .newYork]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let mixedDay = months[5].days.first { $0.dayOfMonth == 1 }
        #expect(mixedDay?.regions == [.california, .newYork])
    }

    @Test func regionTotalsCountDistinctDaysSortedByCount() throws {
        let days = [
            DayPresence(date: day(2026, 6, 1), regions: [.california]),
            DayPresence(date: day(2026, 6, 2), regions: [.california, .newYork]),
            DayPresence(date: day(2026, 6, 3), regions: [.california]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let totals = months[5].regionTotals
        #expect(totals == [
            RegionDayTally(region: .california, days: 3),
            RegionDayTally(region: .newYork, days: 1),
        ])
    }

    @Test func regionTotalsAreUnaffectedByFocus() throws {
        let days = [
            DayPresence(date: day(2026, 6, 1), regions: [.california]),
            DayPresence(date: day(2026, 6, 2), regions: [.california, .newYork]),
            DayPresence(date: day(2026, 6, 3), regions: [.newYork]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            focusedRegion: .newYork,
        )
        let june = months[5]
        let californiaOnlyDay = june.days.first { $0.dayOfMonth == 1 }
        let mixedDay = june.days.first { $0.dayOfMonth == 2 }
        // Focus filters the dots ...
        #expect(californiaOnlyDay?.regions == [])
        #expect(mixedDay?.regions == [.newYork])
        // ... but the footer still tallies every region (tie → allCases order).
        #expect(june.regionTotals == [
            RegionDayTally(region: .california, days: 2),
            RegionDayTally(region: .newYork, days: 2),
        ])
    }

    @Test func monthsWithNoPresenceHaveEmptyRegionTotals() throws {
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
        )
        let allEmpty = months.allSatisfy(\.regionTotals.isEmpty)
        #expect(allEmpty)
    }

    @Test func evidenceDaysMarkOnlyMatchingCells() throws {
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            evidenceDays: [day(2026, 6, 10)],
        )
        let june = months[5]
        let markedDay = june.days.first { $0.dayOfMonth == 10 }
        let unmarkedDay = june.days.first { $0.dayOfMonth == 11 }
        #expect(markedDay?.hasEvidence == true)
        #expect(unmarkedDay?.hasEvidence == false)
    }

    @Test func evidenceDaysAreNormalizedToStartOfDay() throws {
        // A mid-day capture time must still flag the whole calendar day.
        let midday = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 10, hour: 15, minute: 30),
        ))
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            evidenceDays: [midday],
        )
        let markedDay = months[5].days.first { $0.dayOfMonth == 10 }
        #expect(markedDay?.hasEvidence == true)
    }
}
