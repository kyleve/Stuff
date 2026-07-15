import Foundation
import RegionKit

/// Pure rules for turning `LocationSample`s and manual day entries into
/// `DayPresence` values and `YearReport`s. No I/O.
///
/// Rule: a day "counts" for a region if **any** sample in that calendar day
/// fell inside the region. A single day can therefore belong to multiple
/// regions (e.g. a CA→NY same-day flight). Additive manual day entries union
/// with GPS-derived attributions for the same day; authoritative manual day
/// entries (`DayPresence.isAuthoritative`) replace them, so a user correction
/// can drop a wrong attribution.
public struct DayAggregator: Sendable {
    public let calendar: Calendar
    public let timeZone: TimeZone

    public init(
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .current,
    ) {
        var cal = calendar
        cal.timeZone = timeZone
        self.calendar = cal
        self.timeZone = timeZone
    }

    public func aggregate(
        samples: [LocationSample],
        attributor: any RegionAttributing,
    ) -> [DayPresence] {
        var dayRegions: [CalendarDay: Set<Region>] = [:]
        for sample in samples {
            let day = CalendarDay(from: sample.timestamp, in: calendar)
            let region = attributor.region(at: sample.coordinate)
            dayRegions[day, default: []].insert(region)
        }
        return dayRegions
            .map { DayPresence(day: $0.key, regions: $0.value) }
            .sorted { $0.day < $1.day }
    }

    /// Group every sample that fell inside `region` by calendar day, keeping
    /// the raw points (coordinate + horizontal accuracy) so the UI can map,
    /// name, and draw an uncertainty radius for them. Samples outside `region`
    /// (per `attributor`) are dropped; days with no in-region samples don't
    /// appear. Days are sorted ascending.
    ///
    /// This intentionally ignores manual day overlays: it reflects where the
    /// device *actually* recorded points, which is what "where was I?" means —
    /// a manually relabeled day simply contributes no GPS coordinates here.
    public func locations(
        in region: Region,
        samples: [LocationSample],
        attributor: any RegionAttributing,
    ) -> [RegionDayLocations] {
        var byDay: [CalendarDay: [RegionDayPoint]] = [:]
        for sample in samples where attributor.region(at: sample.coordinate) == region {
            let day = CalendarDay(from: sample.timestamp, in: calendar)
            byDay[day, default: []].append(RegionDayPoint(
                coordinate: sample.coordinate,
                horizontalAccuracy: sample.horizontalAccuracy,
            ))
        }
        return byDay
            .map { RegionDayLocations(day: $0.key, points: $0.value) }
            .sorted { $0.day < $1.day }
    }

    /// Group the recorded points that fell on `day` by the region they
    /// attribute to, keeping each raw point (coordinate + horizontal accuracy).
    /// Unlike `locations(in:)`, which projects one region across the whole year,
    /// this covers *every* region a single day touched — so the "Fix this day"
    /// screen and the flight-day detail view can plot all of a day's points at
    /// once (e.g. a flight's origin, fly-over, and destination in one map).
    /// Like `locations(in:)` it reflects recorded points, not manual overlays.
    public func pointsByRegion(
        onDay day: CalendarDay,
        samples: [LocationSample],
        attributor: any RegionAttributing,
    ) -> [Region: [RegionDayPoint]] {
        var byRegion: [Region: [RegionDayPoint]] = [:]
        for sample in samples where CalendarDay(from: sample.timestamp, in: calendar) == day {
            let region = attributor.region(at: sample.coordinate)
            byRegion[region, default: []].append(RegionDayPoint(
                coordinate: sample.coordinate,
                horizontalAccuracy: sample.horizontalAccuracy,
            ))
        }
        return byRegion
    }

    /// One representative coordinate per region: the point inside the most
    /// heavily sampled ~5km cell for that region. Lets the Elsewhere cards show
    /// a single "where" teaser (e.g. the city you spent the most time in)
    /// without geocoding every point. Regions with no samples are absent.
    public func representativeCoordinates(
        samples: [LocationSample],
        attributor: any RegionAttributing,
    ) -> [Region: Coordinate] {
        let precision = 20.0
        var tallies: [Region: [Int: CellTally]] = [:]
        for sample in samples {
            let region = attributor.region(at: sample.coordinate)
            let latBucket = Int((sample.coordinate.latitude * precision).rounded())
            let lngBucket = Int((sample.coordinate.longitude * precision).rounded())
            let cell = latBucket &* 100_000 &+ lngBucket
            if let existing = tallies[region]?[cell] {
                tallies[region]?[cell] = CellTally(
                    count: existing.count + 1,
                    coordinate: existing.coordinate,
                )
            } else {
                tallies[region, default: [:]][cell] = CellTally(
                    count: 1,
                    coordinate: sample.coordinate,
                )
            }
        }
        var representatives: [Region: Coordinate] = [:]
        for (region, cells) in tallies {
            if let dominant = cells.max(by: { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count < rhs.value.count
                }
                return lhs.key > rhs.key
            }) {
                representatives[region] = dominant.value.coordinate
            }
        }
        return representatives
    }

    /// Running tally of one grid cell while picking a region's representative
    /// coordinate: how many samples landed in the cell, and the first
    /// coordinate seen there (used verbatim so the pin sits on real data).
    private struct CellTally {
        let count: Int
        let coordinate: Coordinate
    }

    public func report(
        for year: Int,
        samples: [LocationSample],
        manualDays: [DayPresence] = [],
        attributor: any RegionAttributing,
    ) -> YearReport {
        var dayRegions: [CalendarDay: Set<Region>] = [:]
        for day in aggregate(samples: samples, attributor: attributor) {
            dayRegions[day.day, default: []].formUnion(day.regions)
        }
        // Additive manual days union with GPS (backfilling a region GPS
        // missed). Authoritative manual days are applied afterward so a user
        // correction *replaces* whatever GPS — or an earlier additive overlay
        // — produced for that day, letting them remove a wrong attribution.
        for day in manualDays where !day.isAuthoritative {
            dayRegions[day.day, default: []].formUnion(day.regions)
        }
        for day in manualDays where day.isAuthoritative {
            dayRegions[day.day] = day.regions
        }

        let yearDays = dayRegions
            .filter { $0.key.year == year }
            .map { DayPresence(day: $0.key, regions: $0.value) }
            .sorted { $0.day < $1.day }

        var totals: [Region: Int] = [:]
        for day in yearDays {
            for region in day.regions {
                totals[region, default: 0] += 1
            }
        }

        return YearReport(year: year, days: yearDays, totals: totals)
    }

    /// Half-open `DateInterval` spanning the requested calendar year in this
    /// aggregator's calendar and timezone: `start` is the first instant of
    /// `year`, `end` is the first instant of `year + 1`. `WhereStore`
    /// implementations must therefore filter as `timestamp >= start &&
    /// timestamp < end` so the first instant of the next year is excluded
    /// (and not double-counted by the next year's report).
    public func yearInterval(year: Int) -> DateInterval {
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        let start = calendar.date(from: startComponents) ?? Date(timeIntervalSince1970: 0)
        var endComponents = DateComponents()
        endComponents.year = year + 1
        endComponents.month = 1
        endComponents.day = 1
        let end = calendar.date(from: endComponents) ?? start
        return DateInterval(start: start, end: end)
    }
}
