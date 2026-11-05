import Foundation
import RegionKit
import WhereCore

/// A maximal run of consecutive calendar days the user was present in one
/// region — e.g. "California, Jan 1 – Feb 3". A transition day that belongs to
/// two regions ends one stint and starts the next, so adjacent stints can
/// share an endpoint date.
public struct RegionStint: Hashable, Sendable, Identifiable {
    public struct ID: Hashable, Sendable {
        public let region: Region
        public let start: CalendarDay
    }

    public let region: Region
    public let start: CalendarDay
    public let end: CalendarDay

    public var dayCount: Int {
        start.days(through: end).count
    }

    public var id: ID {
        ID(region: region, start: start)
    }

    public init(region: Region, start: CalendarDay, end: CalendarDay) {
        precondition(start <= end, "A stay must have ordered logical dates")
        self.region = region
        self.start = start
        self.end = end
    }
}

/// Builds a chronological timeline of `RegionStint`s from a `YearReport`. This
/// is presentation logic derived from `DayPresence`, so it lives in `WhereUI`
/// alongside the views that render it.
public enum PresenceTimeline {
    /// Group each region's present days into maximal consecutive runs, then
    /// flatten and sort by start date (ties broken by end date, then by the
    /// catalog's canonical order). `report.days` is already sorted ascending and
    /// has one entry per calendar day, so each region's dates are unique.
    public static func stints(from report: YearReport) -> [RegionStint] {
        var datesByRegion: [Region: [CalendarDay]] = [:]
        for day in report.days {
            for region in day.regions {
                datesByRegion[region, default: []].append(day.day)
            }
        }

        var stints: [RegionStint] = []
        for (region, dates) in datesByRegion {
            let sorted = dates.sorted()
            guard var runStart = sorted.first else { continue }
            var previous = runStart
            for date in sorted.dropFirst() {
                if previous.adding(days: 1) == date {
                    previous = date
                } else {
                    stints.append(RegionStint(
                        region: region,
                        start: runStart,
                        end: previous,
                    ))
                    runStart = date
                    previous = date
                }
            }
            stints.append(RegionStint(
                region: region,
                start: runStart,
                end: previous,
            ))
        }

        return stints.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            return regionOrder(lhs.region) < regionOrder(rhs.region)
        }
    }

    private static func regionOrder(_ region: Region) -> Int {
        Region.declarationOrder[region, default: 0]
    }
}
