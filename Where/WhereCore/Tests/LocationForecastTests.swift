import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct LocationForecastTests {
    @Test(arguments: [PlanningTestSupport.day(1, 1), PlanningTestSupport.day(3, 31)])
    func historicalPatternWaitsForThreeCompleteMonths(today: CalendarDay) {
        #expect(LocationForecast.estimate(
            region: .newYork,
            report: PlanningTestSupport.report(asOf: today, counts: [:]),
            asOf: PlanningTestSupport.date(today),
            calendar: PlanningTestSupport.calendar,
            planning: PlanningSnapshot(stays: [], homeRegion: nil),
        ) == nil)
    }

    @Test func historicalPatternBeginsOnAprilFirstAndUsesElapsedCalendarDays() throws {
        let today = PlanningTestSupport.day(4, 1)
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: PlanningTestSupport.report(asOf: today, counts: [.newYork: 91]),
            asOf: PlanningTestSupport.date(today),
            calendar: PlanningTestSupport.calendar,
            planning: PlanningSnapshot(stays: [], homeRegion: nil),
        ))
        #expect(forecast.elapsedDays == 91)
        #expect(forecast.estimatedTotalDays == DayBounds(exact: 365))
    }

    @Test func homeWorksOnJanuaryFirstWithoutInventingMissingRecordedDays() throws {
        let today = PlanningTestSupport.day(1, 1)
        let forecast = try #require(LocationForecast.estimate(
            region: .california,
            report: PlanningTestSupport.report(asOf: today, counts: [:]),
            asOf: PlanningTestSupport.date(today),
            calendar: PlanningTestSupport.calendar,
            planning: PlanningSnapshot(stays: [], homeRegion: .california),
        ))
        #expect(forecast.yearToDateDays == 0)
        #expect(forecast.estimatedTotalDays == DayBounds(exact: 364))
        #expect(forecast.gapPolicy == .home(.california))
    }

    @Test(arguments: [2025, 2027], [Region?.none, .some(.california)])
    func otherReportYearsHaveNoAnnualForecast(year: Int, home: Region?) {
        #expect(LocationForecast.estimate(
            region: .newYork,
            report: YearReport(year: year, days: [], totals: [:]),
            asOf: PlanningTestSupport.date(PlanningTestSupport.day(7, 1)),
            calendar: PlanningTestSupport.calendar,
            planning: PlanningSnapshot(stays: [], homeRegion: home),
        ) == nil)
    }

    @Test func usesActualUniqueDaysThroughTodayInsteadOfWholeYearTotals() throws {
        let today = PlanningTestSupport.day(7, 1)
        let recorded = DayPresence(day: today, regions: [.newYork])
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: YearReport(year: 2026, days: [
                recorded,
                recorded,
                DayPresence(day: PlanningTestSupport.day(8, 1), regions: [.newYork]),
                DayPresence(day: PlanningTestSupport.day(7, 1, year: 2025), regions: [.newYork]),
            ], totals: [.newYork: 300]),
            asOf: PlanningTestSupport.date(today),
            calendar: PlanningTestSupport.calendar,
            planning: PlanningSnapshot(stays: [], homeRegion: .california),
        ))
        #expect(forecast.yearToDateDays == 1)
        #expect(forecast.estimatedTotalDays == DayBounds(exact: 1))
    }

    @Test func separateNYCReturnsFillHomeGapsAndHistoricalGaps() throws {
        let today = PlanningTestSupport.day(9, 13)
        let stays = try [
            PlanningTestSupport.stay(
                region: .newYork,
                arrival: PlanningTestSupport.day(9, 13),
                departure: PlanningTestSupport.day(9, 20),
            ),
            PlanningTestSupport.stay(
                region: .newYork,
                arrival: PlanningTestSupport.day(10, 15),
                latestArrival: PlanningTestSupport.day(10, 17),
                departure: PlanningTestSupport.day(10, 30),
                latestDeparture: PlanningTestSupport.day(11, 4),
            ),
            PlanningTestSupport.stay(
                region: .newYork,
                arrival: PlanningTestSupport.day(12, 10),
                latestArrival: PlanningTestSupport.day(12, 12),
                departure: PlanningTestSupport.day(12, 20),
                latestDeparture: PlanningTestSupport.day(12, 22),
            ),
        ]
        let report = PlanningTestSupport.report(
            asOf: today,
            counts: [.newYork: 64, .california: 192],
        )
        for home in [Region?.none, .some(.california)] {
            let planning = PlanningSnapshot(stays: stays, homeRegion: home)
            let ny = try #require(LocationForecast.estimate(
                region: .newYork,
                report: report,
                asOf: PlanningTestSupport.date(today),
                calendar: PlanningTestSupport.calendar,
                planning: planning,
            ))
            let ca = try #require(LocationForecast.estimate(
                region: .california,
                report: report,
                asOf: PlanningTestSupport.date(today),
                calendar: PlanningTestSupport.calendar,
                planning: planning,
            ))
            #expect(ny.elapsedDays == 256)
            #expect(ny.plannedDays == DayBounds(lower: 30, upper: 41))
            #expect(ca.plannedDays == DayBounds(exact: 0))
            #expect(ny.estimatedTotalDays == (home == nil
                    ? DayBounds(lower: 113, upper: 122) : DayBounds(lower: 94, upper: 105)))
            #expect(ca.estimatedTotalDays == (home == nil
                    ? DayBounds(lower: 243, upper: 252) : DayBounds(lower: 260, upper: 271)))
        }
    }

    @Test func opposingStayChoicesProduceBoundsThatAllShortOrAllLongMiss() throws {
        let today = PlanningTestSupport.day(12, 20)
        let stays = try [
            PlanningTestSupport.stay(
                region: .newYork,
                arrival: PlanningTestSupport.day(12, 21),
                departure: PlanningTestSupport.day(12, 22),
                latestDeparture: PlanningTestSupport.day(12, 24),
            ),
            PlanningTestSupport.stay(
                region: .california,
                arrival: PlanningTestSupport.day(12, 26),
                departure: PlanningTestSupport.day(12, 27),
                latestDeparture: PlanningTestSupport.day(12, 29),
            ),
        ]
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: PlanningTestSupport.report(asOf: today, counts: [.newYork: 177]),
            asOf: PlanningTestSupport.date(today),
            calendar: PlanningTestSupport.calendar,
            planning: PlanningSnapshot(stays: stays, homeRegion: nil),
        ))
        // Mathematical endpoints are 181.5 and 183.5; all-short/all-long both give 182.5.
        #expect(forecast.estimatedTotalDays == DayBounds(lower: 181, upper: 184))
    }

    @Test func overlappingPlansDeduplicateWithinRegionsAndKeepSharedDays() throws {
        let today = PlanningTestSupport.day(12, 20)
        let stays = try [
            PlanningTestSupport.stay(
                region: .newYork,
                arrival: PlanningTestSupport.day(12, 21),
                departure: PlanningTestSupport.day(12, 22),
                latestDeparture: PlanningTestSupport.day(12, 24),
            ),
            PlanningTestSupport.stay(
                region: .newYork,
                arrival: PlanningTestSupport.day(12, 23),
                departure: PlanningTestSupport.day(12, 25),
            ),
            PlanningTestSupport.stay(
                region: .california,
                arrival: PlanningTestSupport.day(12, 24),
                departure: PlanningTestSupport.day(12, 25),
                latestDeparture: PlanningTestSupport.day(12, 27),
            ),
        ]
        for home in [Region?.none, .some(.california)] {
            for region in [Region.newYork, .california] {
                let forecast = try #require(LocationForecast.estimate(
                    region: region,
                    report: PlanningTestSupport.report(
                        asOf: today,
                        counts: [.newYork: 177, .california: 177],
                    ),
                    asOf: PlanningTestSupport.date(today),
                    calendar: PlanningTestSupport.calendar,
                    planning: PlanningSnapshot(stays: stays + stays, homeRegion: home),
                ))
                let expected: DayBounds = if home != nil {
                    DayBounds(exact: region == .newYork ? 182 : 185)
                } else {
                    region == .newYork ? DayBounds(lower: 184, upper: 185) : DayBounds(
                        lower: 182,
                        upper: 183,
                    )
                }
                #expect(forecast.estimatedTotalDays == expected)
            }
        }
    }

    @Test func yearClippingExcludesTodayAndHandlesLeapDayAndFuturePlans() throws {
        let today = PlanningTestSupport.day(2, 28, year: 2028)
        let stays = try [
            PlanningTestSupport.stay(
                region: .newYork,
                arrival: today,
                departure: PlanningTestSupport.day(2, 29, year: 2028),
            ),
            PlanningTestSupport.stay(
                region: .newYork,
                arrival: PlanningTestSupport.day(1, 1, year: 2029),
                departure: PlanningTestSupport.day(1, 10, year: 2029),
            ),
        ]
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: PlanningTestSupport.report(asOf: today, counts: [:]),
            asOf: PlanningTestSupport.date(today),
            calendar: PlanningTestSupport.calendar,
            planning: PlanningSnapshot(stays: stays, homeRegion: .california),
        ))
        #expect(forecast.plannedDays == DayBounds(exact: 1))
        #expect(forecast.estimatedTotalDays == DayBounds(exact: 1))
    }

    @Test func yearEndContainsRecordedDaysOnly() throws {
        let today = PlanningTestSupport.day(12, 31)
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: today,
            departure: PlanningTestSupport.day(2, 1, year: 2027),
        )
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: PlanningTestSupport.report(asOf: today, counts: [.newYork: 91]),
            asOf: PlanningTestSupport.date(today),
            calendar: PlanningTestSupport.calendar,
            planning: PlanningSnapshot(stays: [stay], homeRegion: .newYork),
        ))
        #expect(forecast.estimatedTotalDays == DayBounds(exact: 91))
        #expect(forecast.projectedRemainingDays == DayBounds(exact: 0))
    }

    @Test(arguments: ["America/New_York", "America/Los_Angeles"])
    func endpointDaysStayFixedWhenTheCalendarTimeZoneChanges(zone: String) throws {
        let today = PlanningTestSupport.day(9, 13)
        var calendar = PlanningTestSupport.calendar
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: today,
            departure: PlanningTestSupport.day(9, 20),
        )
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: PlanningTestSupport.report(asOf: today, counts: [.newYork: 64]),
            asOf: today.startOfDay(in: calendar),
            calendar: calendar,
            planning: PlanningSnapshot(stays: [stay], homeRegion: .california),
        ))
        #expect(forecast.plannedDays == DayBounds(exact: 7))
        #expect(forecast.estimatedTotalDays == DayBounds(exact: 71))
    }

    @Test func boundsMatchEveryFeasibleScenarioWithIndependentWindowsAndOverlaps() throws {
        let today = PlanningTestSupport.day(12, 20)
        let elapsed = 354
        let future = today.adding(days: 1).days(through: PlanningTestSupport.day(12, 31))
        let stays = try [
            PlanningTestSupport.stay(
                region: .newYork,
                arrival: PlanningTestSupport.day(12, 21),
                latestArrival: PlanningTestSupport.day(12, 22),
                departure: PlanningTestSupport.day(12, 23),
                latestDeparture: PlanningTestSupport.day(12, 24),
            ),
            PlanningTestSupport.stay(
                region: .california,
                arrival: PlanningTestSupport.day(12, 22),
                latestArrival: PlanningTestSupport.day(12, 23),
                departure: PlanningTestSupport.day(12, 24),
                latestDeparture: PlanningTestSupport.day(12, 25),
            ),
            PlanningTestSupport.stay(
                region: .newYork,
                arrival: PlanningTestSupport.day(12, 24),
                departure: PlanningTestSupport.day(12, 24),
                latestDeparture: PlanningTestSupport.day(12, 26),
            ),
        ]
        let choices = try stays.map { stay in
            try stay.arrival.earliest.days(through: stay.arrival.latest).flatMap { start in
                try stay.departure.earliest.days(through: stay.departure.latest).map { end in
                    try PlanningTestSupport.stay(
                        region: stay.region,
                        arrival: start,
                        departure: end,
                        stayID: stay.id,
                    )
                }
            }
        }
        for home in [Region?.none, .some(.california)] {
            for region in [Region.newYork, .california, .canada] {
                let recorded = region == .canada ? 0 : 177
                let gapWeight = home.map { $0 == region ? elapsed : 0 } ?? recorded
                var minimum = Int.max
                var maximum = 0
                for first in choices[0] {
                    for second in choices[1] {
                        for third in choices[2] {
                            let scenario = [first, second, third]
                            var numerator = recorded * elapsed
                            for day in future {
                                let present = scenario.filter { $0.longestRange.contains(day) }
                                if present.contains(where: { $0.region == region }) {
                                    numerator += elapsed
                                } else if present.isEmpty {
                                    numerator += gapWeight
                                }
                            }
                            minimum = min(minimum, numerator)
                            maximum = max(maximum, numerator)
                        }
                    }
                }
                let expected = minimum == maximum
                    ? DayBounds(exact: (minimum + elapsed / 2) / elapsed)
                    : DayBounds(lower: minimum / elapsed, upper: (maximum + elapsed - 1) / elapsed)
                let forecast = try #require(LocationForecast.estimate(
                    region: region,
                    report: PlanningTestSupport.report(
                        asOf: today,
                        counts: [.newYork: 177, .california: 177],
                    ),
                    asOf: PlanningTestSupport.date(today),
                    calendar: PlanningTestSupport.calendar,
                    planning: PlanningSnapshot(stays: stays, homeRegion: home),
                ))
                #expect(forecast.estimatedTotalDays == expected)
            }
        }
    }
}
