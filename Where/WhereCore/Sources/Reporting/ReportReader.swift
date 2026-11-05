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
    let history: LocationHistoryReader

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
            try await store.readSnapshot {
                let projection = try await history.projection(
                    for: .days(dayRange(for: year)),
                    calendar: aggregator.calendar,
                    attributor: attributor,
                )
                let manuals = try await store.manualDays(in: dayRange(for: year))
                return try await report(for: year, projection: projection, manualDays: manuals)
            }
        }
    }

    /// Return the exact assessed content an exporter may use. No second read can change the
    /// content between the eligibility check and document generation. Backups remain lossless.
    public func exportableYearReport(for year: Int) async throws -> YearReport {
        let report = try await yearReport(for: year)
        try report.completeness.requireComplete()
        return report
    }

    /// Encode only the immutable report that passed the export gate. A later import cannot
    /// substitute unassessed content while the document is prepared.
    public func exportableYearCSV(for year: Int) async throws -> HistoryReportCSV {
        try await HistoryReportCSV(report: exportableYearReport(for: year))
    }

    /// Read a year's aggregate report and its primary-region recorded locations
    /// from the same samples snapshot. A new fix can leave `report` equal while
    /// changing `primaryRegionLocations`, so presentation models keep the full
    /// value as their refresh identity rather than inventing a change counter.
    public func yearReportDetails(
        for year: Int,
    ) async throws -> YearReportDetails {
        try await Self.logger.measure(.yearReportDetails, budget: .seconds(1)) {
            try await store.readSnapshot {
                let projection = try await history.projection(
                    for: .days(dayRange(for: year)),
                    calendar: aggregator.calendar,
                    attributor: attributor,
                )
                let manuals = try await store.manualDays(in: dayRange(for: year))
                let report = try await report(
                    for: year,
                    projection: projection,
                    manualDays: manuals,
                )
                let primaryRegions = try await store.trackedRegions()
                let locations = aggregator.locations(
                    in: primaryRegions,
                    history: projection.samples,
                )
                return YearReportDetails(
                    elsewhereInput: ElsewhereInput(
                        report: report,
                        primaryRegions: primaryRegions,
                        history: projection,
                        manualDays: manuals,
                        calendar: aggregator.calendar,
                    ),
                    primaryRegionLocations: locations,
                )
            }
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
            try await store.readSnapshot {
                let contextDays = CalendarDay(year: year - 1, month: 12, day: 31)
                    ... CalendarDay(year: year + 1, month: 1, day: 1)
                let attribution = try await history.attributionSnapshot(attributor)
                let projection = try await history.projection(
                    for: .days(contextDays),
                    calendar: aggregator.calendar,
                    attributor: attribution,
                )
                let generation = try await store.dataGeneration()
                let manuals = try await store.manualDays(in: dayRange(for: year))
                let report = try await report(
                    for: year,
                    projection: projection,
                    manualDays: manuals,
                )
                let reportingSamples = try await projection
                    .reportingSamples(primaryRegions: store.trackedRegions())
                let otherLocations = aggregator.locations(
                    in: .other,
                    history: reportingSamples,
                )
                let otherDayCoordinates = Dictionary(
                    uniqueKeysWithValues: otherLocations.map {
                        ($0.day, $0.points.map(\.coordinate))
                    },
                )
                return try await DataIssueReads(
                    report: report,
                    otherDayCoordinates: otherDayCoordinates,
                    daySamples: DaySamples(
                        history: projection.samples,
                        calendar: aggregator.calendar,
                    ),
                    history: projection,
                    manualDays: manuals,
                    primaryRegions: store.primaryRegions().map(\.region),
                    dataGenerationID: generation.id,
                    dismissedIssueIDs: store.dismissedIssueIDs(),
                    attribution: attribution,
                    correctionAttribution: history.correctionAttribution(
                        for: projection,
                        attributor: attribution,
                    ),
                )
            }
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
    /// day for maps and location previews. Elsewhere uses its resolved snapshot.
    /// Manual overlays don't contribute coordinates (see `DayAggregator`).
    public func locations(in region: Region, year: Int) async throws -> [RegionDayLocations] {
        try await locations(in: [region], year: year)[region] ?? []
    }

    /// The raw coordinates recorded inside several regions during `year`,
    /// grouped by region and day. Reads and attributes the year's samples once,
    /// so a surface such as Locations can populate several pieces of artwork
    /// without repeating the store read for every region.
    public func locations(
        in regions: Set<Region>,
        year: Int,
    ) async throws -> [Region: [RegionDayLocations]] {
        try await Self.logger.measure(.regionLocations, budget: .seconds(1)) {
            try await store.readSnapshot {
                let projection = try await history.projection(
                    for: .days(dayRange(for: year)),
                    calendar: aggregator.calendar,
                    attributor: attributor,
                )
                return try await aggregator.locations(
                    in: regions,
                    history: projection.reportingSamples(primaryRegions: store.trackedRegions()),
                )
            }
        }
    }

    /// The recorded points for a single calendar `day`, grouped by the region
    /// they attribute to, so the "Fix this day" screen and the flight-day detail
    /// view can map every point of a multi-region day at once. Reads only that
    /// day's samples (a half-open [start-of-day, next-day) window). Manual
    /// overlays don't contribute coordinates (see `DayAggregator`).
    public func locations(onDay day: CalendarDay) async throws -> [Region: [RegionDayPoint]] {
        try await Self.logger.measure(.dayLocations, budget: .milliseconds(500)) {
            try await store.readSnapshot {
                let projection = try await history.projection(
                    for: .days(day ... day),
                    calendar: aggregator.calendar,
                    attributor: attributor,
                )
                return try await aggregator.pointsByRegion(
                    onDay: day,
                    history: projection.reportingSamples(primaryRegions: store.trackedRegions()),
                )
            }
        }
    }

    /// One representative coordinate per region for `year` — the most heavily
    /// sampled spot in each — so the Elsewhere cards can show a "where" teaser
    /// with a single geocode per region.
    public func representativeCoordinates(for year: Int) async throws -> [Region: Coordinate] {
        try await Self.logger.measure(.representativeCoordinates, budget: .seconds(1)) {
            try await store.readSnapshot {
                let projection = try await history.projection(
                    for: .days(dayRange(for: year)),
                    calendar: aggregator.calendar,
                    attributor: attributor,
                )
                return try await aggregator.representativeCoordinates(
                    history: projection.reportingSamples(primaryRegions: store.trackedRegions()),
                )
            }
        }
    }

    private func report(
        for year: Int,
        projection: LocationHistoryProjection,
        manualDays: [DayPresence],
    ) async throws -> YearReport {
        try await aggregator.report(
            for: year,
            history: projection.reportingSamples(primaryRegions: store.trackedRegions()),
            manualDays: manualDays,
            completeness: projection.completeness(in: dayRange(for: year)),
        )
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
    public let history: LocationHistoryProjection
    public let manualDays: [DayPresence]
    public let primaryRegions: [Region]
    public let dataGenerationID: WhereDataGenerationID
    public let dismissedIssueIDs: Set<DataIssueID>
    public let attribution: any RegionAttributing
    public let correctionAttribution: any RegionAttributing

    public init(
        report: YearReport,
        otherDayCoordinates: [CalendarDay: [Coordinate]],
        daySamples: DaySamples,
        history: LocationHistoryProjection,
        manualDays: [DayPresence],
        primaryRegions: [Region],
        dataGenerationID: WhereDataGenerationID,
        dismissedIssueIDs: Set<DataIssueID>,
        attribution: any RegionAttributing,
        correctionAttribution: any RegionAttributing,
    ) {
        self.report = report
        self.otherDayCoordinates = otherDayCoordinates
        self.daySamples = daySamples
        self.history = history
        self.manualDays = manualDays
        self.primaryRegions = primaryRegions
        self.dataGenerationID = dataGenerationID
        self.dismissedIssueIDs = dismissedIssueIDs
        self.attribution = attribution
        self.correctionAttribution = correctionAttribution
    }
}
