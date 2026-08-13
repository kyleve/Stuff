import Foundation
import RegionKit

/// A region's independently calculated current-year residency estimate.
///
/// This result deliberately contains only the estimate and its inputs. A future
/// residency goal (for example, “55% of the year”) can compare against it
/// without becoming another forecasting policy or changing planned-stay math.
public struct LocationForecast: Hashable, Sendable {
    public let region: Region
    public let year: Int
    public let yearToDateDays: Int
    public let elapsedDays: Int
    public let plannedDays: Int
    public let projectedRemainingDays: Double
    public let estimatedTotalDays: Int

    public var estimatedFractionOfYear: Double {
        let daysInYear = CalendarDay.yearRange(year).lowerBound
            .days(through: CalendarDay.lastDay(ofYear: year)).count
        guard daysInYear > 0 else { return 0 }
        return Double(estimatedTotalDays) / Double(daysInYear)
    }

    /// Estimate a current year's total once three complete calendar months have
    /// elapsed. Returns `nil` before April 1 and for any non-current report.
    public static func estimate(
        region: Region,
        report: YearReport,
        asOf date: Date,
        calendar: Calendar,
        plannedStay: PlannedStay?,
    ) -> LocationForecast? {
        let today = CalendarDay(from: date, in: calendar)
        guard report.year == today.year else { return nil }
        guard today >= CalendarDay(year: report.year, month: 4, day: 1) else { return nil }

        let firstDay = CalendarDay(year: report.year, month: 1, day: 1)
        let lastDay = CalendarDay.lastDay(ofYear: report.year)
        let elapsedDays = firstDay.days(through: today).count
        let yearLength = firstDay.days(through: lastDay).count
        guard elapsedDays > 0, yearLength > 0 else { return nil }

        let yearToDateDays = report.totals[region, default: 0]
        let baselineRate = Double(yearToDateDays) / Double(elapsedDays)
        let tomorrow = today.adding(days: 1)

        let matchingStay = plannedStay.flatMap { stay in
            stay.region == region && stay.through >= today ? stay : nil
        }
        let plannedEnd = matchingStay.map { min($0.through, lastDay) }
        let plannedDays = plannedEnd.map { tomorrow.days(through: $0).count } ?? 0
        let projectionStart = plannedEnd?.adding(days: 1) ?? tomorrow
        let remainingDays = projectionStart.days(through: lastDay).count
        let projectedRemainingDays = baselineRate * Double(remainingDays)
        let estimated = Double(yearToDateDays + plannedDays) + projectedRemainingDays

        return LocationForecast(
            region: region,
            year: report.year,
            yearToDateDays: yearToDateDays,
            elapsedDays: elapsedDays,
            plannedDays: plannedDays,
            projectedRemainingDays: projectedRemainingDays,
            estimatedTotalDays: min(yearLength, max(0, Int(estimated.rounded()))),
        )
    }
}
