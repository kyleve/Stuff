import Foundation
import RegionKit
import WhereCore

/// A maximal run of consecutive calendar days the user was present in one
/// region — e.g. "California, Jan 1 – Feb 3". A transition day that belongs to
/// two regions ends one stint and starts the next, so adjacent stints can
/// share an endpoint date.
public struct RegionStint: Hashable, Sendable, Identifiable {
    public let region: Region
    public let start: Date
    public let end: Date
    public let dayCount: Int

    public var id: String {
        "\(region.rawValue)@\(start.timeIntervalSinceReferenceDate)"
    }

    public init(region: Region, start: Date, end: Date, dayCount: Int) {
        self.region = region
        self.start = start
        self.end = end
        self.dayCount = dayCount
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
    public static func stints(
        from report: YearReport,
        calendar: Calendar = .current,
    ) -> [RegionStint] {
        var datesByRegion: [Region: [Date]] = [:]
        for day in report.days {
            let startOfDay = day.startOfDay(in: calendar)
            for region in day.regions {
                datesByRegion[region, default: []].append(startOfDay)
            }
        }

        var stints: [RegionStint] = []
        for (region, dates) in datesByRegion {
            let sorted = dates.sorted()
            guard var runStart = sorted.first else { continue }
            var previous = runStart
            var count = 1
            for date in sorted.dropFirst() {
                if isConsecutive(previous, date, calendar: calendar) {
                    previous = date
                    count += 1
                } else {
                    stints.append(RegionStint(
                        region: region,
                        start: runStart,
                        end: previous,
                        dayCount: count,
                    ))
                    runStart = date
                    previous = date
                    count = 1
                }
            }
            stints.append(RegionStint(
                region: region,
                start: runStart,
                end: previous,
                dayCount: count,
            ))
        }

        return stints.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            return regionOrder(lhs.region) < regionOrder(rhs.region)
        }
    }

    private static func isConsecutive(
        _ previous: Date,
        _ candidate: Date,
        calendar: Calendar,
    ) -> Bool {
        guard let next = calendar.date(byAdding: .day, value: 1, to: previous) else { return false }
        return calendar.isDate(next, inSameDayAs: candidate)
    }

    private static func regionOrder(_ region: Region) -> Int {
        Region.declarationOrder[region, default: 0]
    }
}
