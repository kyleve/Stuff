import Foundation
import RegionKit

/// The pure read path over a `WhereStore`: turns persisted samples + manual
/// days into the `YearReport` and location projections the UI, reminders, and
/// daily-summary all consume.
///
/// Holds no mutable state (just the store + the calendar/attribution policy),
/// so it's a cheap `Sendable` value that each collaborator that needs reads can
/// keep its own copy of, rather than routing every read back through one actor.
public struct ReportReader: Sendable {
    let store: any WhereStore
    let aggregator: DayAggregator
    let attributor: RegionAttributor

    /// The half-open date interval covering `year` in the aggregator's calendar.
    func yearInterval(year: Int) -> DateInterval {
        aggregator.yearInterval(year: year)
    }

    /// The inclusive `CalendarDay` range spanning `year`.
    func dayRange(for year: Int) -> ClosedRange<CalendarDay> {
        CalendarDay.yearRange(year)
    }

    /// Read everything in `year` and aggregate it into a snapshot-stable report.
    public func yearReport(for year: Int) async throws -> YearReport {
        let interval = aggregator.yearInterval(year: year)
        let samples = try await store.samples(in: interval)
        let manuals = try await store.manualDays(in: dayRange(for: year))
        return aggregator.report(
            for: year,
            samples: samples,
            manualDays: manuals,
            attributor: attributor,
        )
    }

    /// Every persisted `LocationSample` recorded during `year`, unaggregated, so
    /// callers that need per-fix timestamps (the speed-based `FlightDayDetector`
    /// via `DataIssueScanner`) can walk the raw stream rather than the collapsed
    /// `YearReport`. Ordering is the store's; callers that need chronology sort.
    public func samples(inYear year: Int) async throws -> [LocationSample] {
        try await store.samples(in: aggregator.yearInterval(year: year))
    }

    /// The manual-day records (backfills and authoritative overrides) the user
    /// asserted for `year`, so the "logged days" management screen can list,
    /// edit, and delete them. Unlike `yearReport`, these are the raw user
    /// entries — the `isAuthoritative` flag and `audit` trail are preserved
    /// rather than merged away.
    public func manualDays(inYear year: Int) async throws -> [DayPresence] {
        try await store.manualDays(in: dayRange(for: year))
    }

    /// The raw coordinates recorded inside `region` during `year`, grouped by
    /// day, so the Elsewhere drill-in can map and name where you actually were.
    /// Manual overlays don't contribute coordinates (see `DayAggregator`).
    public func locations(in region: Region, year: Int) async throws -> [RegionDayLocations] {
        let interval = aggregator.yearInterval(year: year)
        let samples = try await store.samples(in: interval)
        return aggregator.locations(in: region, samples: samples, attributor: attributor)
    }

    /// The recorded points for a single calendar `day`, grouped by the region
    /// they attribute to, so the "Fix this day" screen and the flight-day detail
    /// view can map every point of a multi-region day at once. Reads only that
    /// day's samples (a half-open [start-of-day, next-day) window). Manual
    /// overlays don't contribute coordinates (see `DayAggregator`).
    public func locations(onDay day: CalendarDay) async throws -> [Region: [RegionDayPoint]] {
        let start = day.startOfDay(in: aggregator.calendar)
        guard let end = aggregator.calendar.date(byAdding: .day, value: 1, to: start) else {
            return [:]
        }
        let samples = try await store.samples(in: DateInterval(start: start, end: end))
        return aggregator.pointsByRegion(onDay: day, samples: samples, attributor: attributor)
    }

    /// One representative coordinate per region for `year` — the most heavily
    /// sampled spot in each — so the Elsewhere cards can show a "where" teaser
    /// with a single geocode per region.
    public func representativeCoordinates(for year: Int) async throws -> [Region: Coordinate] {
        let interval = aggregator.yearInterval(year: year)
        let samples = try await store.samples(in: interval)
        return aggregator.representativeCoordinates(samples: samples, attributor: attributor)
    }

    /// Every persisted dismissal key for data-resolution issues.
    public func dismissedIssueKeys() async throws -> Set<String> {
        try await store.dismissedIssueKeys()
    }
}
