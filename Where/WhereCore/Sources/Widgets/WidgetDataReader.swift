import Foundation
import RegionKit
import WhereSurface

/// Everything the Where widgets render, captured as one `Sendable` value:
/// which regions the snapshot's day already counts for, plus the per-region
/// day totals from January 1 through that day.
///
/// `Codable` because the app process publishes this (after each committed
/// store write) to a small JSON file in the shared App Group container,
/// which the widget extension then reads — see `WidgetSnapshotStore`. The
/// raw store never crosses the process boundary.
public struct WidgetSnapshot: Hashable, Sendable, Codable {
    /// Start-of-day (in the reader's calendar) this snapshot describes.
    public let day: Date
    /// The calendar year containing `day`; the year `totals` belongs to.
    public let year: Int
    /// Regions `day` counts for so far. Empty when nothing is logged yet.
    public let dayRegions: Set<Region>
    /// Day counts per region from January 1 of `year` through `day`, inclusive.
    /// A day in two regions counts once for each.
    public let totals: [Region: Int]
    /// The user's picked appearances for their primary regions, carried across
    /// the App Group so the widget process can render each region's chosen
    /// color/emoji/icon (it has no store access and no `WhereSession`, so it
    /// seeds its `RegionStyleResolver` from this). Empty for regions the user
    /// hasn't customized (and for snapshots written before this field existed) —
    /// those fall back to the default look.
    public let appearances: [Region: RegionAppearance]
    /// When the app generated this artifact. Optional only so an artifact
    /// published by an older app version still decodes.
    public let generatedAt: Date?
    /// Presentation-ready data for store-free glance processes. Optional only
    /// for compatibility with artifacts published before WhereSurface existed.
    public let surface: WhereSurfaceSnapshot?

    public init(
        day: Date,
        year: Int,
        dayRegions: Set<Region>,
        totals: [Region: Int],
        appearances: [Region: RegionAppearance],
        generatedAt: Date?,
        surface: WhereSurfaceSnapshot?,
    ) {
        self.day = day
        self.year = year
        self.dayRegions = dayRegions
        self.totals = totals
        self.appearances = appearances
        self.generatedAt = generatedAt
        self.surface = surface
    }

    private enum CodingKeys: String, CodingKey {
        case day, year, dayRegions, totals, appearances, generatedAt, surface
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(Date.self, forKey: .day)
        year = try container.decode(Int.self, forKey: .year)
        dayRegions = try container.decode(Set<Region>.self, forKey: .dayRegions)
        totals = try container.decode([Region: Int].self, forKey: .totals)
        // Additive: snapshots written before `appearances` existed decode to an
        // empty map rather than failing (the widget then uses default looks).
        appearances = try container
            .decodeIfPresent([Region: RegionAppearance].self, forKey: .appearances) ?? [:]
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt)
        surface = try container.decodeIfPresent(WhereSurfaceSnapshot.self, forKey: .surface)
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
    private var history: LocationHistoryReader {
        LocationHistoryReader(store: store)
    }

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
        let samples = try await history.samples(in: interval)
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
        var totalsToDate: [Region: Int] = [:]
        for day in report.days where day.day <= calendarDay {
            for region in day.regions {
                totalsToDate[region, default: 0] += 1
            }
        }
        var appearances: [Region: RegionAppearance] = [:]
        for primary in try await store.primaryRegions() {
            if let appearance = primary.appearance { appearances[primary.region] = appearance }
        }
        let surfaceRegion: (Region) -> WhereSurfaceSnapshot.Region = { region in
            WhereSurfaceSnapshot.Region(
                id: region.rawValue,
                name: region.localizedName,
                emoji: appearances[region]?.emoji,
                symbolName: appearances[region]?.symbolName,
            )
        }
        let todayRegions = Region.inCanonicalOrder(dayRegions).map(surfaceRegion)
        let yearToDate = Region.rankedByDayCount(
            totalsToDate,
            days: { $0.value },
            region: { $0.key },
        )
        .prefix(3)
        .map { total in
            WhereSurfaceSnapshot.DayCount(
                region: surfaceRegion(total.key),
                days: total.value,
            )
        }
        let surface = WhereSurfaceSnapshot(
            day: startOfDay,
            todayRegions: todayRegions,
            year: year,
            yearToDate: Array(yearToDate),
        )
        return WidgetSnapshot(
            day: startOfDay,
            year: year,
            dayRegions: dayRegions,
            totals: totalsToDate,
            appearances: appearances,
            generatedAt: date,
            surface: surface,
        )
    }
}
