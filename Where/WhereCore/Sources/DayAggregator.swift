import Foundation

/// Pure rules for turning `LocationSample`s and manual day entries into
/// `DayPresence` values and `YearReport`s. No I/O.
///
/// Rule: a day "counts" for a region if **any** sample in that calendar day
/// fell inside the region. A single day can therefore belong to multiple
/// regions (e.g. a CA→NY same-day flight). Manual day entries union with
/// GPS-derived attributions for the same day.
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
        attributor: RegionAttributor,
    ) -> [DayPresence] {
        var dayRegions: [Date: Set<Region>] = [:]
        for sample in samples {
            let dayStart = calendar.startOfDay(for: sample.timestamp)
            let region = attributor.region(at: sample.coordinate)
            dayRegions[dayStart, default: []].insert(region)
        }
        return dayRegions
            .map { DayPresence(date: $0.key, regions: $0.value) }
            .sorted { $0.date < $1.date }
    }

    public func report(
        for year: Int,
        samples: [LocationSample],
        manualDays: [DayPresence] = [],
        attributor: RegionAttributor,
    ) -> YearReport {
        var dayRegions: [Date: Set<Region>] = [:]
        for day in aggregate(samples: samples, attributor: attributor) {
            dayRegions[day.date, default: []].formUnion(day.regions)
        }
        for day in manualDays {
            let dayStart = calendar.startOfDay(for: day.date)
            dayRegions[dayStart, default: []].formUnion(day.regions)
        }

        let yearDays = dayRegions
            .filter { calendar.component(.year, from: $0.key) == year }
            .map { DayPresence(date: $0.key, regions: $0.value) }
            .sorted { $0.date < $1.date }

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
