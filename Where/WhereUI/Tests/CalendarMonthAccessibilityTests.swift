import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct CalendarMonthAccessibilityTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 14 * 3600)!
        return calendar
    }

    private func day(_ number: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: 7, day: number)
    }

    private func month(
        regions: [Int: Set<Region>],
        evidence: Set<Int> = [],
        flights: Set<Int> = [],
        missing: Set<Int> = [],
        focusedRegion: Region? = nil,
    ) throws -> CalendarMonth {
        try PresenceCalendar.month(
            year: 2026,
            month: 7,
            regionsByDay: Dictionary(uniqueKeysWithValues: regions.map { (day($0.key), $0.value) }),
            calendar: calendar,
            referenceDate: day(15).startOfDay(in: calendar),
            missingDates: Set(missing.map(day)),
            evidenceDays: Set(evidence.map(day)),
            flightDays: Set(flights.map(day)),
            focusedRegion: focusedRegion,
        )
    }

    @Test func readsStaySpansInOrderAndKeepsDatedBadgesInsideTheStay() throws {
        let month = try month(
            regions: [
                1: [.california],
                2: [.california],
                3: [.california],
                4: [.california, .newYork],
                5: [.newYork],
                6: [.newYork],
            ],
            evidence: [1, 3, 4],
            flights: [2, 3, 4],
        )
        let result = CalendarMonthAccessibility(
            month: month,
            calendar: calendar,
            memberships: { _ in [:] },
            planningSummary: [],
        )

        #expect(result
            .label ==
            "July 2026. California: 4 days, New York: 3 days, and 1 day in California and New York")
        #expect(result
            .value ==
            "July 1 through July 3: California, Attachment on July 1 and July 3, and Flight on July 2 through July 3; July 4: California, New York, Attachment on July 4, and Flight on July 4; July 5 through July 6: New York")
    }

    @Test func preservesMissingLocationsAndBadgesWithoutRegionalPresence() throws {
        let result = try CalendarMonthAccessibility(
            month: month(regions: [:], evidence: [2], flights: [1], missing: [1, 2]),
            calendar: calendar,
            memberships: { _ in [:] },
            planningSummary: [],
        )

        #expect(result.label == "July 2026. No days logged")
        #expect(result
            .value ==
            "July 1 through July 2: Needs a location, Attachment on July 2, and Flight on July 1")
    }

    @Test func distinguishesRecordedPlannedPossibleAndHomeSpans() throws {
        let month = try month(regions: [1: [.newYork]])
        let result = CalendarMonthAccessibility(
            month: month,
            calendar: calendar,
            memberships: { cell in
                switch cell.dayOfMonth {
                    case 2, 3: [.newYork: .planned(.certain)]
                    case 4: [.newYork: .planned(.possible)]
                    case 5: [.california: .homeAssumed(.possible)]
                    case 6: [.california: .homeAssumed(.certain)]
                    default: [:]
                }
            },
            planningSummary: [
                .init(
                    region: .newYork,
                    plannedDays: .init(lower: 2, upper: 3),
                    homeDays: .init(exact: 0),
                ),
                .init(
                    region: .california,
                    plannedDays: .init(exact: 0),
                    homeDays: .init(lower: 1, upper: 2),
                ),
            ],
        )

        #expect(result.label.contains("New York: Possible: 2–3 days"))
        #expect(result.label.contains("California: Assumed at Home: 1–2 days"))
        #expect(result
            .value ==
            "July 1: New York; July 2 through July 3: New York: Planned; July 4: New York: Possible; July 5: California: Possibly at Home; July 6: California: Assumed at Home")
    }

    @Test func focusedCalendarKeepsAllTotalsButOnlyReadsDisplayedStays() throws {
        let result = try CalendarMonthAccessibility(
            month: month(
                regions: [1: [.california], 2: [.newYork], 3: [.california]],
                focusedRegion: .california,
            ),
            calendar: calendar,
            memberships: { _ in [:] },
            planningSummary: [],
        )

        #expect(result.label.contains("California: 2 days"))
        #expect(result.label.contains("New York: 1 day"))
        #expect(result.value == "July 1: California; July 3: California")
    }

    @Test func keepsOneStayAcrossWeekBoundariesAndClipsItToTheMonth() throws {
        let result = try CalendarMonthAccessibility(
            month: month(regions: Dictionary(uniqueKeysWithValues: (1 ... 31).map { (
                $0,
                [.california],
            ) })),
            calendar: calendar,
            memberships: { _ in [:] },
            planningSummary: [],
        )

        #expect(result.value == "July 1 through July 31: California")
    }

    @Test func emptyMonthDoesNotReadEveryEmptyDay() throws {
        let result = try CalendarMonthAccessibility(
            month: month(regions: [:]),
            calendar: calendar,
            memberships: { _ in [:] },
            planningSummary: [],
        )

        #expect(result.label == "July 2026. No days logged")
        #expect(result.value.isEmpty)
    }
}
