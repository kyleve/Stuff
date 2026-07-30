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
    private static let logger = WhereLog.reporting(ReportReaderLog.self)

    let store: any WhereStore
    let aggregator: DayAggregator
    let attributor: any RegionAttributing
    private var history: LocationHistoryReader {
        LocationHistoryReader(store: store)
    }

    /// The half-open date interval covering `year` in the aggregator's calendar.
    func yearInterval(year: Int) -> DateInterval {
        aggregator.yearInterval(year: year)
    }

    /// The inclusive `CalendarDay` range spanning `year`.
    func dayRange(for year: Int) -> ClosedRange<CalendarDay> {
        CalendarDay.yearRange(year)
    }

    /// Read everything in `year` and aggregate it into a snapshot-stable report.
    ///
    /// The report is the app's hottest read — the calendar, the reminders badge,
    /// the daily summary, the widget snapshot, and the issue scan all go through
    /// it — so it is spanned with a budget: past a second, whatever asked for it
    /// is visibly waiting.
    public func yearReport(for year: Int) async throws -> YearReport {
        try await Self.logger.measure(.yearReport, budget: .seconds(1)) {
            let interval = aggregator.yearInterval(year: year)
            let samples = try await history.samples(in: interval)
            let manuals = try await store.manualDays(in: dayRange(for: year))
            return aggregator.report(
                for: year,
                samples: samples,
                manualDays: manuals,
                attributor: attributor,
            )
        }
    }

    /// Everything a data-issue scan needs from a **single** year-samples read:
    /// the aggregated `report`, the `.other` day coordinates border-drift checks
    /// use, and the raw GPS fixes (lazily grouped in `DaySamples`) the
    /// speed-based detector walks. Reads the year's samples once, so the scanner
    /// no longer fetches them three times over (report + `.other` locations +
    /// raw); the `DaySamples` grouping is itself deferred until a detector asks.
    public func dataIssueReads(for year: Int) async throws -> DataIssueReads {
        try await Self.logger.measure(.dataIssueReads, budget: .seconds(2)) {
            let samples = try await history.samples(in: aggregator.yearInterval(year: year))
            let manuals = try await store.manualDays(in: dayRange(for: year))
            let report = aggregator.report(
                for: year,
                samples: samples,
                manualDays: manuals,
                attributor: attributor,
            )
            let otherLocations = aggregator.locations(
                in: .other,
                samples: samples,
                attributor: attributor,
            )
            let otherDayCoordinates = Dictionary(
                uniqueKeysWithValues: otherLocations.map { ($0.day, $0.points.map(\.coordinate)) },
            )
            return DataIssueReads(
                report: report,
                otherDayCoordinates: otherDayCoordinates,
                daySamples: DaySamples(samples: samples, calendar: aggregator.calendar),
            )
        }
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
        try await Self.logger.measure(.regionLocations, budget: .seconds(1)) {
            let interval = aggregator.yearInterval(year: year)
            let samples = try await history.samples(in: interval)
            return aggregator.locations(in: region, samples: samples, attributor: attributor)
        }
    }

    /// The recorded points for a single calendar `day`, grouped by the region
    /// they attribute to, so the "Fix this day" screen and the flight-day detail
    /// view can map every point of a multi-region day at once. Reads only that
    /// day's samples (a half-open [start-of-day, next-day) window). Manual
    /// overlays don't contribute coordinates (see `DayAggregator`).
    public func locations(onDay day: CalendarDay) async throws -> [Region: [RegionDayPoint]] {
        try await Self.logger.measure(.dayLocations, budget: .milliseconds(500)) {
            let start = day.startOfDay(in: aggregator.calendar)
            guard let end = aggregator.calendar.date(byAdding: .day, value: 1, to: start) else {
                return [:]
            }
            let samples = try await history.samples(in: DateInterval(start: start, end: end))
            return aggregator.pointsByRegion(onDay: day, samples: samples, attributor: attributor)
        }
    }

    /// One representative coordinate per region for `year` — the most heavily
    /// sampled spot in each — so the Elsewhere cards can show a "where" teaser
    /// with a single geocode per region.
    public func representativeCoordinates(for year: Int) async throws -> [Region: Coordinate] {
        try await Self.logger.measure(.representativeCoordinates, budget: .seconds(1)) {
            let interval = aggregator.yearInterval(year: year)
            let samples = try await history.samples(in: interval)
            return aggregator.representativeCoordinates(samples: samples, attributor: attributor)
        }
    }

    /// Every persisted dismissed data-resolution issue id.
    public func dismissedIssueIDs() async throws -> Set<DataIssueID> {
        try await store.dismissedIssueIDs()
    }
}

/// The one-read bundle `DataIssueScanner` builds a `DataIssueInput` from, so the
/// scan reads the year's samples once rather than per projection.
public struct DataIssueReads: Sendable {
    public let report: YearReport
    public let otherDayCoordinates: [CalendarDay: [Coordinate]]
    public let daySamples: DaySamples

    public init(
        report: YearReport,
        otherDayCoordinates: [CalendarDay: [Coordinate]],
        daySamples: DaySamples,
    ) {
        self.report = report
        self.otherDayCoordinates = otherDayCoordinates
        self.daySamples = daySamples
    }
}
