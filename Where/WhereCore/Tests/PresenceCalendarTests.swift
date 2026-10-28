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

    @Test func flightAndEvidenceBadgesCoexistWithoutPresenceAndSurviveFocus() throws {
        let flightDay = CalendarDay(year: 2026, month: 1, day: 3)
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: day(2026, 1, 3),
            evidenceDays: [flightDay],
            flightDays: [flightDay],
            focusedRegion: .california,
        )
        let cell = months[0].days[2]
        #expect(cell.hasFlight && cell.hasEvidence && cell.isToday)
        #expect(cell.regions.isEmpty)
        #expect(!months[0].days[1].hasFlight)
        #expect(months[0].regionTotals.isEmpty)
    }

    @Test func monthsFromReportReturnsTwelveMonthsInOrder() throws {
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
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
            flightDays: [],
        )
        #expect(months.count == expected)
    }

    @Test func leadingBlankCountForJanuary2026() throws {
        // Jan 1 2026 is a Thursday; with Sunday-first, that is 4 leading blanks.
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
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
            flightDays: [],
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
            DayPresence(date: day(2026, 3, 15), in: calendar, regions: [.newYork, .california]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
        )
        let marchDay = months[2].days.first { $0.dayOfMonth == 15 }
        #expect(marchDay?.regions == [.california, .newYork])
    }

    @Test func dayCountMatchesCalendarRange() throws {
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
        )
        let february = months[1]
        #expect(february.days.count == 28)
    }

    @Test func dayWithNoPresenceHasEmptyRegions() throws {
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
        )
        let januaryFirst = months[0].days[0]
        #expect(januaryFirst.dayOfMonth == 1)
        #expect(januaryFirst.regions.isEmpty)
    }

    @Test func dayWithPresenceIncludesMatchingRegions() throws {
        let days = [
            DayPresence(date: day(2026, 6, 10), in: calendar, regions: [.canada, .europeanUnion]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
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
            flightDays: [],
        )
        let marchDay = months[2].days.first { $0.dayOfMonth == 4 }
        #expect(marchDay?.isToday == true)
        #expect(months[2].isCurrentMonth == true)
    }

    @Test func marksMissingDatesAsNeedingAttention() throws {
        let missing = CalendarDay(year: 2026, month: 2, day: 5)
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            missingDates: [missing],
            flightDays: [],
        )
        let februaryDay = months[1].days.first { $0.dayOfMonth == 5 }
        #expect(februaryDay?.needsAttention == true)
    }

    @Test func yearReportCalendarMonthsMatchesPresenceCalendar() throws {
        let report = report([
            DayPresence(date: day(2026, 1, 1), in: calendar, regions: [.california]),
        ])
        let reference = referenceDate(2026, 1, 1)
        let fromReport = try report.calendarMonths(
            calendar: calendar,
            referenceDate: reference,
            flightDays: [],
        )
        let fromPresence = try PresenceCalendar.months(
            from: report,
            calendar: calendar,
            referenceDate: reference,
            flightDays: [],
        )
        #expect(fromReport == fromPresence)
    }

    @Test func focusedRegionKeepsOnlyThatRegionsDots() throws {
        let days = [
            DayPresence(date: day(2026, 6, 1), in: calendar, regions: [.california, .newYork]),
            DayPresence(date: day(2026, 6, 2), in: calendar, regions: [.newYork]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
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
            DayPresence(date: day(2026, 6, 1), in: calendar, regions: [.california, .newYork]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
        )
        let mixedDay = months[5].days.first { $0.dayOfMonth == 1 }
        #expect(mixedDay?.regions == [.california, .newYork])
    }

    @Test func regionTotalsCountDistinctDaysSortedByCount() throws {
        let days = [
            DayPresence(date: day(2026, 6, 1), in: calendar, regions: [.california]),
            DayPresence(date: day(2026, 6, 2), in: calendar, regions: [.california, .newYork]),
            DayPresence(date: day(2026, 6, 3), in: calendar, regions: [.california]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
        )
        let totals = months[5].regionTotals
        #expect(totals == [
            RegionDayTally(region: .california, days: 3),
            RegionDayTally(region: .newYork, days: 1),
        ])
    }

    @Test func regionCombinationTotalsCountExactSetsInStableOrder() throws {
        let days = [
            DayPresence(
                date: day(2026, 6, 1),
                in: calendar,
                regions: [.newYork, .california],
            ),
            DayPresence(
                date: day(2026, 6, 2),
                in: calendar,
                regions: [.california, .newYork],
            ),
            DayPresence(
                date: day(2026, 6, 3),
                in: calendar,
                regions: [.canada, .california],
            ),
            DayPresence(
                date: day(2026, 6, 4),
                in: calendar,
                regions: [.california, .newYork, .canada],
            ),
            DayPresence(date: day(2026, 6, 5), in: calendar, regions: [.california]),
        ]

        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
        )

        #expect(months[5].regionCombinationTotals == [
            RegionCombinationDayTally(regions: [.california, .newYork], days: 2),
            RegionCombinationDayTally(
                regions: [.california, .newYork, .canada],
                days: 1,
            ),
            RegionCombinationDayTally(regions: [.california, .canada], days: 1),
        ])
    }

    @Test func regionCombinationTotalsAreUnaffectedByFocus() throws {
        let days = [
            DayPresence(
                date: day(2026, 6, 1),
                in: calendar,
                regions: [.california, .newYork],
            ),
        ]

        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
            focusedRegion: .california,
        )

        #expect(months[5].regionCombinationTotals == [
            RegionCombinationDayTally(regions: [.california, .newYork], days: 1),
        ])
    }

    @Test func regionTotalsAreUnaffectedByFocus() throws {
        let days = [
            DayPresence(date: day(2026, 6, 1), in: calendar, regions: [.california]),
            DayPresence(date: day(2026, 6, 2), in: calendar, regions: [.california, .newYork]),
            DayPresence(date: day(2026, 6, 3), in: calendar, regions: [.newYork]),
        ]
        let months = try PresenceCalendar.months(
            from: report(days),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            flightDays: [],
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
            flightDays: [],
        )
        let allEmpty = months.allSatisfy(\.regionTotals.isEmpty)
        #expect(allEmpty)
    }

    @Test func evidenceDaysMarkOnlyMatchingCells() throws {
        let months = try PresenceCalendar.months(
            from: report([]),
            calendar: calendar,
            referenceDate: referenceDate(2026, 6, 15),
            evidenceDays: [CalendarDay(year: 2026, month: 6, day: 10)],
            flightDays: [],
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
            evidenceDays: [CalendarDay(from: midday, in: calendar)],
            flightDays: [],
        )
        let markedDay = months[5].days.first { $0.dayOfMonth == 10 }
        #expect(markedDay?.hasEvidence == true)
    }
}
