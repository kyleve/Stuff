import Foundation

/// Everything the Where widgets render, captured as one `Sendable` value:
/// which regions the snapshot's day already counts for, plus the per-region
/// day totals for the calendar year containing that day.
public struct WidgetSnapshot: Hashable, Sendable {
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

/// Read-side query API for the widget extension: wraps a `WhereStore` and
/// the pure `DayAggregator` without any of `WhereController`'s GPS or
/// reminder machinery, which must not run in a widget process. Production
/// widget wiring pairs this with `SwiftDataStore.readOnly()`.
public struct WidgetDataReader: Sendable {
    private let store: any WhereStore
    private let aggregator: DayAggregator
    private let attributor: RegionAttributor

    public init(
        store: any WhereStore,
        aggregator: DayAggregator = DayAggregator(),
        attributor: RegionAttributor = .shared,
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
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        let interval = aggregator.yearInterval(year: year)
        let samples = try await store.samples(in: interval)
        let manualDays = try await store.manualDays(in: interval)
        let report = aggregator.report(
            for: year,
            samples: samples,
            manualDays: manualDays,
            attributor: attributor,
        )
        let dayRegions = report.days
            .first { calendar.startOfDay(for: $0.date) == day }?
            .regions ?? []
        return WidgetSnapshot(day: day, year: year, dayRegions: dayRegions, totals: report.totals)
    }
}
