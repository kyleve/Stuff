import Foundation

/// The pure read path over a `WhereStore`: turns persisted samples + manual
/// days into the `YearReport` and location projections the UI, reminders, and
/// daily-summary all consume.
///
/// Holds no mutable state (just the store + the calendar/attribution policy),
/// so it's a cheap `Sendable` value that each collaborator that needs reads can
/// keep its own copy of, rather than routing every read back through one actor.
struct ReportReader {
    let store: any WhereStore
    let aggregator: DayAggregator
    let attributor: RegionAttributor

    /// The half-open date interval covering `year` in the aggregator's calendar.
    func yearInterval(year: Int) -> DateInterval {
        aggregator.yearInterval(year: year)
    }

    /// Read everything in `year` and aggregate it into a snapshot-stable report.
    func yearReport(for year: Int) async throws -> YearReport {
        let interval = aggregator.yearInterval(year: year)
        let samples = try await store.samples(in: interval)
        let manuals = try await store.manualDays(in: interval)
        return aggregator.report(
            for: year,
            samples: samples,
            manualDays: manuals,
            attributor: attributor,
        )
    }

    /// The raw coordinates recorded inside `region` during `year`, grouped by
    /// day, so the Elsewhere drill-in can map and name where you actually were.
    /// Manual overlays don't contribute coordinates (see `DayAggregator`).
    func locations(in region: Region, year: Int) async throws -> [RegionDayLocations] {
        let interval = aggregator.yearInterval(year: year)
        let samples = try await store.samples(in: interval)
        return aggregator.locations(in: region, samples: samples, attributor: attributor)
    }

    /// One representative coordinate per region for `year` — the most heavily
    /// sampled spot in each — so the Elsewhere cards can show a "where" teaser
    /// with a single geocode per region.
    func representativeCoordinates(for year: Int) async throws -> [Region: Coordinate] {
        let interval = aggregator.yearInterval(year: year)
        let samples = try await store.samples(in: interval)
        return aggregator.representativeCoordinates(samples: samples, attributor: attributor)
    }
}
