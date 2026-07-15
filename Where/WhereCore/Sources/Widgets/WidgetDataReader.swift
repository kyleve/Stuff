import Foundation
import RegionKit

/// Everything the Where widgets render, captured as one `Sendable` value:
/// which regions the snapshot's day already counts for, plus the per-region
/// day totals for the calendar year containing that day.
///
/// `Codable` because the app process publishes this (after each committed
/// store write) to a small JSON file in the shared App Group container,
/// which the widget extension then reads — see `WidgetSnapshotStore`. The
/// raw store never crosses the process boundary.
public struct WidgetSnapshot: Hashable, Sendable, Codable {
    /// Start-of-day (in the reader's calendar) this snapshot describes.
    public let day: Date
    /// The calendar year containing `day`; the year `totals` covers.
    public let year: Int
    /// Regions `day` counts for so far. Empty when nothing is logged yet.
    public let dayRegions: Set<Region>
    /// Day counts per region for `year` (a `YearReport.totals`). A day in
    /// two regions counts once for each.
    public let totals: [Region: Int]

    public init(day: Date, year: Int, dayRegions: Set<Region>, totals: [Region: Int]) {
        self.day = day
        self.year = year
        self.dayRegions = dayRegions
        self.totals = totals
    }
}

/// Computes a `WidgetSnapshot` from a `WhereStore` and the pure
/// `DayAggregator`, without any of the GPS or reminder machinery. Runs in the
/// *app* process: `WidgetSnapshotPublisher` uses it to rebuild the snapshot
/// after each committed write and publish it to the shared App Group file
/// (`WidgetSnapshotStore`). The widget process only reads that file — it never
/// touches the store.
public struct WidgetDataReader: Sendable {
    private let store: any WhereStore
    private let aggregator: DayAggregator
    private let attributor: any RegionAttributing

    public init(
        store: any WhereStore,
        aggregator: DayAggregator = DayAggregator(),
        attributor: any RegionAttributing = RegionAttributor.shared,
    ) {
        self.store = store
        self.aggregator = aggregator
        self.attributor = attributor
    }

    /// Build the snapshot for the calendar day containing `date`, reading
    /// that day's year from the store. Same aggregation rules as the app's
    /// year report, so the widget and the app never disagree on a count.
    public func snapshot(asOf date: Date) async throws -> WidgetSnapshot {
        let calendar = aggregator.calendar
        let startOfDay = calendar.startOfDay(for: date)
        let calendarDay = CalendarDay(from: date, in: calendar)
        let year = calendarDay.year
        let interval = aggregator.yearInterval(year: year)
        let dayRange = CalendarDay.yearRange(year)
        let samples = try await store.samples(in: interval)
        let manualDays = try await store.manualDays(in: dayRange)
        let report = aggregator.report(
            for: year,
            samples: samples,
            manualDays: manualDays,
            attributor: attributor,
        )
        let dayRegions = report.days
            .first { $0.day == calendarDay }?
            .regions ?? []
        return WidgetSnapshot(
            day: startOfDay,
            year: year,
            dayRegions: dayRegions,
            totals: report.totals,
        )
    }
}
