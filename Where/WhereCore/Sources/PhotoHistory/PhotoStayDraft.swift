import Foundation
import RegionKit

/// An inclusive range of regional presence. Ranges for different regions may overlap.
public struct PhotoStay: Hashable, Sendable, Identifiable {
    public let region: Region
    public let start: CalendarDay
    public let end: CalendarDay
    public var id: Self {
        self
    }

    public init(region: Region, start: CalendarDay, end: CalendarDay) {
        self.region = region
        self.start = start
        self.end = end
    }
}

public struct ReviewedPhotoPoint: Sendable {
    public let original: DatedPhotoLocation
    public let day: CalendarDay
    public let region: Region
}

public struct ReviewedPhotoHistory: Sendable {
    public let points: [ReviewedPhotoPoint]
    /// Only dates the user supplied or confirmed independently of an observed point.
    public let assertedDays: [DayPresence]
}

public struct PhotoStayDraft: Sendable {
    public let scan: PhotoLocationScan
    private struct Presence: Hashable {
        let day: CalendarDay
        let region: Region
    }

    private var assignments: [Presence: Presence] = [:]

    private var observedDays: [CalendarDay: Set<Region>] {
        var result: [CalendarDay: Set<Region>] = [:]
        for presence in assignments.values {
            result[presence.day, default: []].insert(presence.region)
        }
        return result
    }

    private var assertions: [CalendarDay: Set<Region>] = [:]
    private var confirmed: Set<PhotoStay> = []
    private var dismissed: Set<PhotoStay> = []

    public init(scan: PhotoLocationScan) {
        self.scan = scan
        for point in scan.points {
            let source = Presence(day: point.day, region: point.region)
            assignments[source] = source
        }
    }

    public func observedDayCount(in stay: PhotoStay) -> Int {
        Set(assignments.values.filter {
            $0.region == stay.region && (stay.start ... stay.end).contains($0.day)
        }.map(\.day)).count
    }

    public var bounds: ClosedRange<CalendarDay> {
        CalendarDay.yearRange(scan.through.year).lowerBound ... scan.through
    }

    private var proposals: [PhotoStay] {
        let observations = observedDays
        let days = observations.keys.sorted()
        return zip(days, days.dropFirst()).compactMap { left, right in
            guard right > left.adding(days: 1), right <= left.adding(days: 8),
                  let first = observations[left], let last = observations[right] else { return nil }
            let shared = first.intersection(last).subtracting([.other])
            guard shared.count == 1, let region = shared.first else { return nil }
            let gap = PhotoStay(
                region: region,
                start: left.adding(days: 1),
                end: right.adding(days: -1),
            )
            guard confirmed.contains(gap) || gap.start.days(through: gap.end)
                .allSatisfy({ assertions[$0, default: []].isEmpty })
            else { return nil }
            return gap
        }
    }

    public var confirmedGaps: [PhotoStay] {
        proposals.filter(confirmed.contains)
    }

    public var pendingGaps: [PhotoStay] {
        proposals.filter { !confirmed.contains($0) && !dismissed.contains($0) }
    }

    public mutating func decide(_ gap: PhotoStay, include: Bool) {
        guard pendingGaps.contains(gap) else { return }
        if include { confirmed.insert(gap) } else { dismissed.insert(gap) }
    }

    private var acceptedAssertions: [CalendarDay: Set<Region>] {
        var result = assertions
        for gap in confirmed {
            for day in gap.start
                .days(through: gap.end)
            {
                result[day, default: []].insert(gap.region)
            }
        }
        return result
    }

    public var report: YearReport {
        var regions = acceptedAssertions
        for (day, values) in observedDays {
            regions[day, default: []].formUnion(values)
        }
        var totals: [Region: Int] = [:]
        let days = regions.compactMap { day, places -> DayPresence? in
            guard !places.isEmpty else { return nil }
            for place in places {
                totals[place, default: 0] += 1
            }
            return DayPresence(day: day, regions: places)
        }
        return YearReport(year: scan.through.year, days: days, totals: totals)
    }

    /// Replace the selected region's run, leaving all co-present regions alone.
    @discardableResult
    public mutating func edit(_ original: PhotoStay?, to replacement: PhotoStay?) -> Bool {
        for stay in [original, replacement].compactMap(\.self) {
            guard stay.start <= stay.end, bounds.contains(stay.start),
                  bounds.contains(stay.end) else { return false }
        }
        if let original {
            let days = Array(original.start.days(through: original.end))
            let newDays = replacement.map { Array($0.start.days(through: $0.end)) } ?? []
            let movesRange = days.count == newDays.count && original.start != replacement?.start
            let previous = assignments
            for (offset, day) in days.enumerated() {
                let targetDay = movesRange ? newDays[offset] : day
                let old = Presence(day: day, region: original.region)
                for (source, effective) in previous where effective == old {
                    assignments[source] = replacement.flatMap {
                        ($0.start ... $0.end).contains(targetDay)
                            ? Presence(day: targetDay, region: $0.region) : nil
                    }
                }
                assertions[day]?.remove(original.region)
            }
        }
        if let replacement {
            let observed = observedDays
            for day in replacement.start.days(through: replacement.end)
                where observed[day]?.contains(replacement.region) != true
            {
                assertions[day, default: []].insert(replacement.region)
            }
        }
        let valid = Set(proposals)
        confirmed.formIntersection(valid)
        dismissed.formIntersection(valid)
        return true
    }

    public var approved: ReviewedPhotoHistory {
        let points = scan.points.compactMap { original -> ReviewedPhotoPoint? in
            guard let effective = assignments[Presence(day: original.day, region: original.region)]
            else { return nil }
            return ReviewedPhotoPoint(
                original: original,
                day: effective.day,
                region: effective.region,
            )
        }
        return ReviewedPhotoHistory(
            points: points,
            assertedDays: acceptedAssertions.compactMap { day, regions in
                regions.isEmpty ? nil : DayPresence(day: day, regions: regions)
            },
        )
    }
}
