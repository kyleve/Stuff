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

    // MARK: missingDayKeys

    @Test func emptyPresenceMissesEveryDayThroughTheGivenDay() {
        let through = Self.day(2026, 1, 5)
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: through,
            present: [],
            calendar: Self.calendar,
        )
        #expect(missing == [
            Self.day(2026, 1, 1),
            Self.day(2026, 1, 2),
            Self.day(2026, 1, 3),
            Self.day(2026, 1, 4),
            Self.day(2026, 1, 5),
        ])
    }

    @Test func presentDaysAreExcludedAndThroughDayIsInclusive() {
        let through = Self.day(2026, 1, 4)
        let present: Set<Date> = [Self.day(2026, 1, 2), Self.day(2026, 1, 4)]
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: through,
            present: present,
            calendar: Self.calendar,
        )
        #expect(missing == [Self.day(2026, 1, 1), Self.day(2026, 1, 3)])
    }

    @Test func presenceKeysAreNormalizedToStartOfDay() throws {
        // A "present" key carrying a mid-day time should still exclude that day.
        let midday = try #require(
            Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 15)),
        )
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: Self.day(2026, 1, 3),
            present: [midday],
            calendar: Self.calendar,
        )
        #expect(missing == [Self.day(2026, 1, 1), Self.day(2026, 1, 3)])
    }

    @Test func throughInALaterYearClampsToDecemberThirtyFirst() {
        let through = Self.day(2027, 6, 15)
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: through,
            present: [],
            calendar: Self.calendar,
        )
        #expect(missing.first == Self.day(2026, 1, 1))
        #expect(missing.last == Self.day(2026, 12, 31))
        // 2026 is not a leap year.
        #expect(missing.count == 365)
    }

    @Test func throughBeforeStartOfYearYieldsNothing() {
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: Self.day(2025, 12, 31),
            present: [],
            calendar: Self.calendar,
        )
        #expect(missing.isEmpty)
    }

    @Test func leapYearIncludesFebruaryTwentyNinth() {
        let missing = MissingDays.missingDayKeys(
            year: 2024,
            through: Self.day(2024, 12, 31),
            present: [],
            calendar: Self.calendar,
        )
        #expect(missing.contains(Self.day(2024, 2, 29)))
        #expect(missing.count == 366)
    }

    // MARK: backlogCutoff

    @Test func backlogCutoffIsTheStartOfTheDayBeforeToday() throws {
        let now = try #require(
            Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9)),
        )
        let cutoff = MissingDays.backlogCutoff(asOf: now, calendar: Self.calendar)
        #expect(cutoff == Self.day(2026, 1, 4))
    }

    @Test func backlogExcludesTodayEvenWhenUnlogged() {
        let now = Self.day(2026, 1, 5)
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: MissingDays.backlogCutoff(asOf: now, calendar: Self.calendar),
            present: [],
            calendar: Self.calendar,
        )
        // Jan 1–4 are missed; today (Jan 5) is still pending, not in the backlog.
        #expect(missing == [
            Self.day(2026, 1, 1),
            Self.day(2026, 1, 2),
            Self.day(2026, 1, 3),
            Self.day(2026, 1, 4),
        ])
        #expect(!missing.contains(Self.day(2026, 1, 5)))
    }

    @Test func backlogIsEmptyOnNewYearsDay() {
        let now = Self.day(2026, 1, 1)
        let missing = MissingDays.missingDayKeys(
            year: 2026,
            through: MissingDays.backlogCutoff(asOf: now, calendar: Self.calendar),
            present: [],
            calendar: Self.calendar,
        )
        #expect(missing.isEmpty)
    }

    // MARK: ranges

    @Test func rangesCollapseConsecutiveDaysAndSplitOnGaps() {
        let keys = [
            Self.day(2026, 1, 1),
            Self.day(2026, 1, 2),
            Self.day(2026, 1, 3),
            Self.day(2026, 1, 7),
            Self.day(2026, 1, 10),
            Self.day(2026, 1, 11),
        ]
        let ranges = MissingDays.ranges(keys, calendar: Self.calendar)
        #expect(ranges == [
            MissingDayRange(start: Self.day(2026, 1, 1), end: Self.day(2026, 1, 3), dayCount: 3),
            MissingDayRange(start: Self.day(2026, 1, 7), end: Self.day(2026, 1, 7), dayCount: 1),
            MissingDayRange(start: Self.day(2026, 1, 10), end: Self.day(2026, 1, 11), dayCount: 2),
        ])
    }

    @Test func rangesAcrossMonthBoundaryStayContiguous() {
        let keys = [
            Self.day(2026, 1, 30),
            Self.day(2026, 1, 31),
            Self.day(2026, 2, 1),
        ]
        let ranges = MissingDays.ranges(keys, calendar: Self.calendar)
        #expect(ranges == [
            MissingDayRange(start: Self.day(2026, 1, 30), end: Self.day(2026, 2, 1), dayCount: 3),
        ])
    }

    @Test func rangesDeduplicateAndSortUnorderedInput() {
        let keys = [
            Self.day(2026, 3, 2),
            Self.day(2026, 3, 1),
            Self.day(2026, 3, 2),
        ]
        let ranges = MissingDays.ranges(keys, calendar: Self.calendar)
        #expect(ranges == [
            MissingDayRange(start: Self.day(2026, 3, 1), end: Self.day(2026, 3, 2), dayCount: 2),
        ])
    }

    @Test func emptyKeysYieldNoRanges() {
        #expect(MissingDays.ranges([], calendar: Self.calendar).isEmpty)
    }

    @Test func missingRangesConvenienceMatchesManualComposition() {
        let present: Set<Date> = [Self.day(2026, 1, 2)]
        let through = Self.day(2026, 1, 4)
        let ranges = MissingDays.missingRanges(
            year: 2026,
            through: through,
            present: present,
            calendar: Self.calendar,
        )
        #expect(ranges == [
            MissingDayRange(start: Self.day(2026, 1, 1), end: Self.day(2026, 1, 1), dayCount: 1),
            MissingDayRange(start: Self.day(2026, 1, 3), end: Self.day(2026, 1, 4), dayCount: 2),
        ])
    }
}
