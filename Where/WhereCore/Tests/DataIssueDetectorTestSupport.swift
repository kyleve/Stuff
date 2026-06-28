import Foundation
import WhereCore

/// Shared fixtures for the per-detector test files (`MissingDaysDetectorTests`,
/// `BorderDriftDetectorTests`, `AbruptLocationChangeDetectorTests`, and the
/// type-erasure coverage in `DataIssueDetectorTests`), so the `DataIssueInput`
/// builder isn't duplicated across them.
enum DataIssueDetectorFixtures {
    static var calendar: Calendar {
        WhereCoreTestSupport.calendar()
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
        ))!)
    }

    static func input(
        year: Int = 2026,
        days: [DayPresence] = [],
        otherDayCoordinates: [Date: [Coordinate]] = [:],
        primaryRegions: [Region] = [.california, .newYork],
        driftThresholdMeters: Double = 10000,
        now: Date? = nil,
    ) -> DataIssueInput {
        let totals = Dictionary(grouping: days.flatMap(\.regions), by: { $0 }).mapValues(\.count)
        return DataIssueInput(
            year: year,
            report: YearReport(year: year, days: days, totals: totals),
            otherDayCoordinates: otherDayCoordinates,
            primaryRegions: primaryRegions,
            attributor: .shared,
            driftThresholdMeters: driftThresholdMeters,
            calendar: calendar,
            now: now ?? day(year, 6, 15),
        )
    }
}
