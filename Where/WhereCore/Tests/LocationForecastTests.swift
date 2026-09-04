import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct LocationForecastTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func report(days: Int = 91, year: Int = 2026) -> YearReport {
        YearReport(year: year, days: [], totals: [.newYork: days])
    }

    @Test(arguments: [(1, 1), (3, 31)])
    func unavailableUntilThreeFullMonthsHaveElapsed(month: Int, day: Int) {
        #expect(LocationForecast.estimate(
            region: .newYork,
            report: Self.report(),
            asOf: Self.date(month, day),
            calendar: Self.calendar,
            plannedStay: nil,
        ) == nil)
    }

    @Test func becomesAvailableOnAprilFirst() throws {
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: Self.report(),
            asOf: Self.date(4, 1),
            calendar: Self.calendar,
            plannedStay: nil,
        ))

        #expect(forecast.elapsedDays == 91)
        #expect(forecast.estimatedTotalDays == 365)
    }

    @Test func unavailableForAPastReport() {
        #expect(LocationForecast.estimate(
            region: .newYork,
            report: Self.report(year: 2025),
            asOf: Self.date(7, 1),
            calendar: Self.calendar,
            plannedStay: nil,
        ) == nil)
    }

    @Test func annualizesElapsedCalendarDayRate() throws {
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: Self.report(),
            asOf: Self.date(7, 1),
            calendar: Self.calendar,
            plannedStay: nil,
        ))

        #expect(forecast.elapsedDays == 182)
        #expect(forecast.yearToDateDays == 91)
        #expect(forecast.plannedDays == 0)
        #expect(forecast.projectedRemainingDays == 91.5)
        #expect(forecast.estimatedTotalDays == 183)
    }

    @Test func matchingStayCountsThroughItsInclusiveDateThenResumesBaseline() throws {
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: Self.report(),
            asOf: Self.date(7, 1),
            calendar: Self.calendar,
            plannedStay: PlannedStay(
                region: .newYork,
                through: CalendarDay(year: 2026, month: 7, day: 10),
            ),
        ))

        #expect(forecast.plannedDays == 9)
        #expect(forecast.projectedRemainingDays == 87)
        #expect(forecast.estimatedTotalDays == 187)
    }

    @Test func crossYearStayCountsEveryRemainingDayThisYear() throws {
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: Self.report(),
            asOf: Self.date(7, 1),
            calendar: Self.calendar,
            plannedStay: PlannedStay(
                region: .newYork,
                through: CalendarDay(year: 2027, month: 2, day: 1),
            ),
        ))

        #expect(forecast.plannedDays == 183)
        #expect(forecast.projectedRemainingDays == 0)
        #expect(forecast.estimatedTotalDays == 274)
    }

    @Test func anotherRegionsStayReservesItsDaysFromTheProjection() throws {
        let withCaliforniaStay = try #require(LocationForecast.estimate(
            region: .newYork,
            report: Self.report(),
            asOf: Self.date(7, 1),
            calendar: Self.calendar,
            plannedStay: PlannedStay(
                region: .california,
                through: CalendarDay(year: 2026, month: 8, day: 1),
            ),
        ))

        #expect(withCaliforniaStay.plannedDays == 0)
        #expect(withCaliforniaStay.projectedRemainingDays == 76)
        #expect(withCaliforniaStay.estimatedTotalDays == 167)
    }

    @Test func anotherRegionsCrossYearStayLeavesOnlyRecordedDays() throws {
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: Self.report(),
            asOf: Self.date(7, 1),
            calendar: Self.calendar,
            plannedStay: PlannedStay(
                region: .california,
                through: CalendarDay(year: 2027, month: 2, day: 1),
            ),
        ))

        #expect(forecast.plannedDays == 0)
        #expect(forecast.projectedRemainingDays == 0)
        #expect(forecast.estimatedTotalDays == 91)
    }

    @Test func stayEndingTodayDoesNotReserveFutureDays() throws {
        let forecast = try #require(LocationForecast.estimate(
            region: .newYork,
            report: Self.report(),
            asOf: Self.date(7, 1),
            calendar: Self.calendar,
            plannedStay: PlannedStay(
                region: .california,
                through: CalendarDay(year: 2026, month: 7, day: 1),
            ),
        ))

        #expect(forecast.plannedDays == 0)
        #expect(forecast.projectedRemainingDays == 91.5)
        #expect(forecast.estimatedTotalDays == 183)
    }
}
