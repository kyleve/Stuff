import Foundation
import Testing
@testable import WhereCore

struct MissingDaysTests {
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func cday(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    // MARK: missingDayKeys

    @Test func emptyPresenceMissesEveryDayThroughTheGivenDay() {
        let through = Self.cday(2026, 1, 5)
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: through,
            present: [],
        )
        #expect(missing == [
            Self.cday(2026, 1, 1),
            Self.cday(2026, 1, 2),
            Self.cday(2026, 1, 3),
            Self.cday(2026, 1, 4),
            Self.cday(2026, 1, 5),
        ])
    }

    @Test func presentDaysAreExcludedAndThroughDayIsInclusive() {
        let through = Self.cday(2026, 1, 4)
        let present: Set<CalendarDay> = [Self.cday(2026, 1, 2), Self.cday(2026, 1, 4)]
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: through,
            present: present,
        )
        #expect(missing == [Self.cday(2026, 1, 1), Self.cday(2026, 1, 3)])
    }

    @Test func presenceKeysAreNormalizedToStartOfDay() throws {
        // A "present" key derived from a mid-day time should still exclude that day.
        let midday = try #require(
            Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 15)),
        )
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: Self.cday(2026, 1, 3),
            present: [CalendarDay(from: midday, in: Self.calendar)],
        )
        #expect(missing == [Self.cday(2026, 1, 1), Self.cday(2026, 1, 3)])
    }

    @Test func throughInALaterYearClampsToDecemberThirtyFirst() {
        let through = Self.cday(2027, 6, 15)
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: through,
            present: [],
        )
        #expect(missing.first == Self.cday(2026, 1, 1))
        #expect(missing.last == Self.cday(2026, 12, 31))
        // 2026 is not a leap year.
        #expect(missing.count == 365)
    }

    @Test func throughBeforeStartOfYearYieldsNothing() {
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: Self.cday(2025, 12, 31),
            present: [],
        )
        #expect(missing.isEmpty)
    }

    @Test func leapYearIncludesFebruaryTwentyNinth() {
        let missing = MissingDays.missingDayKeys(
            year: 2024,
            through: Self.cday(2024, 12, 31),
            present: [],
        )
        #expect(missing.contains(Self.cday(2024, 2, 29)))
        #expect(missing.count == 366)
    }

    // MARK: backlogCutoff

    @Test func backlogCutoffIsTheStartOfTheDayBeforeToday() throws {
        let now = try #require(
            Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9)),
        )
        let cutoff = MissingDays.backlogCutoff(asOf: now, calendar: Self.calendar)
        #expect(cutoff == Self.cday(2026, 1, 4))
    }

    @Test func backlogExcludesTodayEvenWhenUnlogged() {
        let now = Self.day(2026, 1, 5)
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: MissingDays.backlogCutoff(asOf: now, calendar: Self.calendar),
            present: [],
        )
        // Jan 1–4 are missed; today (Jan 5) is still pending, not in the backlog.
        #expect(missing == [
            Self.cday(2026, 1, 1),
            Self.cday(2026, 1, 2),
            Self.cday(2026, 1, 3),
            Self.cday(2026, 1, 4),
        ])
        #expect(!missing.contains(Self.cday(2026, 1, 5)))
    }

    @Test func backlogIsEmptyOnNewYearsDay() {
        let now = Self.day(2026, 1, 1)
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: MissingDays.backlogCutoff(asOf: now, calendar: Self.calendar),
            present: [],
        )
        #expect(missing.isEmpty)
    }

    // MARK: ranges

    @Test func rangesCollapseConsecutiveDaysAndSplitOnGaps() {
        let keys = [
            Self.cday(2026, 1, 1),
            Self.cday(2026, 1, 2),
            Self.cday(2026, 1, 3),
            Self.cday(2026, 1, 7),
            Self.cday(2026, 1, 10),
            Self.cday(2026, 1, 11),
        ]
        let ranges = MissingDays.ranges(keys)
        #expect(ranges == [
            MissingDayRange(start: Self.cday(2026, 1, 1), end: Self.cday(2026, 1, 3), dayCount: 3),
            MissingDayRange(start: Self.cday(2026, 1, 7), end: Self.cday(2026, 1, 7), dayCount: 1),
            MissingDayRange(
                start: Self.cday(2026, 1, 10),
                end: Self.cday(2026, 1, 11),
                dayCount: 2,
            ),
        ])
    }

    @Test func rangesAcrossMonthBoundaryStayContiguous() {
        let keys = [
            Self.cday(2026, 1, 30),
            Self.cday(2026, 1, 31),
            Self.cday(2026, 2, 1),
        ]
        let ranges = MissingDays.ranges(keys)
        #expect(ranges == [
            MissingDayRange(start: Self.cday(2026, 1, 30), end: Self.cday(2026, 2, 1), dayCount: 3),
        ])
    }

    @Test func rangesDeduplicateAndSortUnorderedInput() {
        let keys = [
            Self.cday(2026, 3, 2),
            Self.cday(2026, 3, 1),
            Self.cday(2026, 3, 2),
        ]
        let ranges = MissingDays.ranges(keys)
        #expect(ranges == [
            MissingDayRange(start: Self.cday(2026, 3, 1), end: Self.cday(2026, 3, 2), dayCount: 2),
        ])
    }

    @Test func emptyKeysYieldNoRanges() {
        #expect(MissingDays.ranges([]).isEmpty)
    }

    @Test func missingRangesConvenienceMatchesManualComposition() {
        let present: Set<CalendarDay> = [Self.cday(2026, 1, 2)]
        let through = Self.cday(2026, 1, 4)
        let ranges = MissingDays.missingRanges(
            year: 2026,
            through: through,
            present: present,
        )
        #expect(ranges == [
            MissingDayRange(start: Self.cday(2026, 1, 1), end: Self.cday(2026, 1, 1), dayCount: 1),
            MissingDayRange(start: Self.cday(2026, 1, 3), end: Self.cday(2026, 1, 4), dayCount: 2),
        ])
    }
}
