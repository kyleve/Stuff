import Foundation
import RegionKit
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

    /// A passive GPS fix at `coordinate`, `hoursAfterStart` into `dayStart`, for
    /// building the timestamp-sorted `daySamples` the speed-based detector walks.
    static func gpsSample(
        dayStart: Date,
        hoursAfterStart: Double,
        _ coordinate: Coordinate,
        source: SampleSource = .gpsSignificantChange,
    ) -> LocationSample {
        LocationSample(
            timestamp: dayStart.addingTimeInterval(hoursAfterStart * 3600),
            coordinate: coordinate,
            horizontalAccuracy: 20,
            source: source,
        )
    }

    static func input(
        year: Int = 2026,
        days: [DayPresence] = [],
        otherDayCoordinates: [Date: [Coordinate]] = [:],
        daySamples: [Date: [LocationSample]] = [:],
        primaryRegions: [Region] = [.california, .newYork],
        driftThresholdMeters: Double = 10000,
        now: Date? = nil,
    ) -> DataIssueInput {
        let totals = Dictionary(grouping: days.flatMap(\.regions), by: { $0 }).mapValues(\.count)
        return DataIssueInput(
            year: year,
            report: YearReport(year: year, days: days, totals: totals),
            otherDayCoordinates: otherDayCoordinates,
            daySamples: daySamples,
            primaryRegions: primaryRegions,
            attributor: .shared,
            driftThresholdMeters: driftThresholdMeters,
            calendar: calendar,
            now: now ?? day(year, 6, 15),
        )
    }
}
