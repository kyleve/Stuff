import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct YearOverviewTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    @Test(arguments: [(2024, 366), (2025, 365)])
    func containsEveryDayInTheYear(argument: (year: Int, count: Int)) throws {
        let referenceDate = try #require(calendar.date(from: DateComponents(
            year: argument.year,
            month: 12,
            day: 31,
        )))
        let overview = YearOverview(
            report: YearReport(year: argument.year, days: [], totals: [:]),
            referenceDate: referenceDate,
            calendar: calendar,
        )

        #expect(overview.dayCount == argument.count)
        #expect(overview.slices.reduce(0) { $0 + $1.days } == argument.count)
    }

    @Test func classifiesRecordedMissingTodayAndFutureDays() throws {
        let referenceDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 15,
        )))
        let report = YearReport(
            year: 2026,
            days: [
                presence(2026, 1, 1, regions: [.california]),
                presence(2026, 1, 2, regions: [.newYork, .california]),
                presence(2026, 7, 16, regions: [.newYork]),
            ],
            totals: [:],
        )
        let overview = YearOverview(
            report: report,
            referenceDate: referenceDate,
            calendar: calendar,
        )

        #expect(overview.day(month: 1, dayOfMonth: 1)?.kind == .region(.california))
        #expect(
            overview.day(month: 1, dayOfMonth: 2)?.kind
                == .multipleLocations([.california, .newYork]),
        )
        #expect(overview.day(month: 7, dayOfMonth: 14)?.kind == .unrecorded)
        #expect(overview.day(month: 7, dayOfMonth: 15)?.kind == .remaining)
        #expect(overview.day(month: 7, dayOfMonth: 16)?.kind == .remaining)
        #expect(overview.recordedDayCount == 2)
    }

    @Test func emptyRegionPresenceIsUnrecorded() throws {
        let referenceDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 2,
        )))
        let overview = YearOverview(
            report: YearReport(
                year: 2026,
                days: [presence(2026, 1, 1, regions: [])],
                totals: [:],
            ),
            referenceDate: referenceDate,
            calendar: calendar,
        )

        #expect(overview.day(month: 1, dayOfMonth: 1)?.kind == .unrecorded)
        #expect(overview.recordedDayCount == 0)
    }

    @Test func pastYearHasNoRemainingDays() throws {
        let referenceDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 15,
        )))
        let overview = YearOverview(
            report: YearReport(year: 2025, days: [], totals: [:]),
            referenceDate: referenceDate,
            calendar: calendar,
        )

        #expect(overview.slices == [.init(id: .unrecorded, days: 365)])
    }

    @Test func slicesRankRegionsThenAppendSpecialCategories() throws {
        let referenceDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 5,
        )))
        let overview = YearOverview(
            report: YearReport(
                year: 2026,
                days: [
                    presence(2026, 1, 1, regions: [.newYork]),
                    presence(2026, 1, 2, regions: [.california]),
                    presence(2026, 1, 3, regions: [.newYork, .california]),
                ],
                totals: [:],
            ),
            referenceDate: referenceDate,
            calendar: calendar,
        )

        #expect(overview.slices.map(\.id) == [
            .region(.california),
            .region(.newYork),
            .multipleLocations,
            .unrecorded,
            .remaining,
        ])
        #expect(overview.slices.reduce(0) { $0 + $1.days } == 365)
    }

    private func presence(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        regions: Set<Region>,
    ) -> DayPresence {
        DayPresence(
            day: CalendarDay(year: year, month: month, day: day),
            regions: regions,
        )
    }
}
