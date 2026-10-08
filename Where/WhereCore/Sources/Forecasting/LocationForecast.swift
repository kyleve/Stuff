import Foundation
import RegionKit

/// Independent bounds on a region's current-year estimate. Bounds describe
/// entered date choices, not confidence in future behavior. Component bounds
/// can occur in different scenarios and must not be added endpoint by endpoint.
public struct LocationForecast: Hashable, Sendable {
    public enum GapPolicy: Hashable, Sendable {
        case historicalPattern
        case home(Region)
    }

    public let region: Region
    public let year: Int
    public let yearToDateDays: Int
    public let elapsedDays: Int
    public let plannedDays: DayBounds
    public let projectedRemainingDays: DayBounds
    public let estimatedTotalDays: DayBounds
    public let gapPolicy: GapPolicy

    public var estimatedFractionOfYear: ClosedRange<Double> {
        let daysInYear = CalendarDay.yearRange(year).lowerBound
            .days(through: CalendarDay.lastDay(ofYear: year)).count
        return Double(estimatedTotalDays.lower) / Double(daysInYear)
            ... Double(estimatedTotalDays.upper) / Double(daysInYear)
    }

    /// Historical forecasts need three complete months. Home forecasts can
    /// begin on January 1. Neither policy estimates a non-current report year.
    public static func estimate(
        region: Region,
        report: YearReport,
        asOf date: Date,
        calendar: Calendar,
        planning: PlanningSnapshot,
    ) -> LocationForecast? {
        let today = CalendarDay(from: date, in: calendar)
        guard report.year == today.year else { return nil }
        guard planning.homeRegion != nil
            || today >= CalendarDay(year: report.year, month: 4, day: 1)
        else { return nil }

        let firstDay = CalendarDay(year: report.year, month: 1, day: 1)
        let lastDay = CalendarDay.lastDay(ofYear: report.year)
        let elapsedDays = firstDay.days(through: today).count
        let futureDays = today.adding(days: 1).days(through: lastDay).count
        let yearToDateDays = Set(report.days.filter {
            $0.day.year == report.year && $0.day <= today && $0.regions.contains(region)
        }.map(\.day)).count
        let gapNumerator = planning.homeRegion.map { $0 == region ? elapsedDays : 0 }
            ?? yearToDateDays
        let coverage = Coverage(
            region: region,
            stays: planning.stays,
            future: PlanningSnapshot.futureRange(intersecting: report.year, asOf: today),
        )

        // An own-region day replaces a gap weight <= 1 or another region's 0;
        // another region replaces only the gap weight. These opposite extrema
        // are therefore attainable even when several uncertain stays overlap.
        let lowerReserved = coverage.certainTarget.union(coverage.possibleOthers).count
        let upperReserved = coverage.possibleTarget.union(coverage.certainOthers).count
        let lowerNumerator = (yearToDateDays + coverage.certainTarget.count) * elapsedDays
            + (futureDays - lowerReserved) * gapNumerator
        let upperNumerator = (yearToDateDays + coverage.possibleTarget.count) * elapsedDays
            + (futureDays - upperReserved) * gapNumerator
        let mostReserved = coverage.possibleTarget.union(coverage.possibleOthers).count
        let leastReserved = coverage.certainTarget.union(coverage.certainOthers).count

        return LocationForecast(
            region: region,
            year: report.year,
            yearToDateDays: yearToDateDays,
            elapsedDays: elapsedDays,
            plannedDays: DayBounds(
                lower: coverage.certainTarget.count,
                upper: coverage.possibleTarget.count,
            ),
            projectedRemainingDays: .rounded(
                lowerNumerator: (futureDays - mostReserved) * gapNumerator,
                upperNumerator: (futureDays - leastReserved) * gapNumerator,
                denominator: elapsedDays,
            ),
            estimatedTotalDays: .rounded(
                lowerNumerator: lowerNumerator,
                upperNumerator: upperNumerator,
                denominator: elapsedDays,
            ),
            gapPolicy: planning.homeRegion.map { .home($0) } ?? .historicalPattern,
        )
    }

    /// Day unions preserve independent plan identity while preventing duplicate
    /// same-region days from inflating an estimate.
    private struct Coverage {
        var certainTarget: Set<CalendarDay> = []
        var possibleTarget: Set<CalendarDay> = []
        var certainOthers: Set<CalendarDay> = []
        var possibleOthers: Set<CalendarDay> = []

        init(region: Region, stays: [PlannedStay], future: ClosedRange<CalendarDay>?) {
            guard let future else { return }
            for stay in stays {
                let certain = PlanningSnapshot.intersection(stay.shortestRange, future)
                    .map { $0.lowerBound.days(through: $0.upperBound) } ?? []
                let possible = PlanningSnapshot.intersection(stay.longestRange, future)
                    .map { $0.lowerBound.days(through: $0.upperBound) } ?? []
                if stay.region == region {
                    certainTarget.formUnion(certain)
                    possibleTarget.formUnion(possible)
                } else {
                    certainOthers.formUnion(certain)
                    possibleOthers.formUnion(possible)
                }
            }
        }
    }
}
