import Foundation
import RegionKit

/// Resolved travel intent and the optional Home region used for future gaps.
/// A nil Home keeps the historical-rate policy. Plans never change recorded days.
public struct PlanningSnapshot: Hashable, Sendable {
    public let stays: [PlannedStay]
    public let homeRegion: Region?

    public init(stays: [PlannedStay], homeRegion: Region?) {
        self.stays = stays
        self.homeRegion = homeRegion
    }

    public func plannedPresence(
        on day: CalendarDay,
        asOf today: CalendarDay,
    ) -> PlanningDayPresence {
        guard day > today else {
            return PlanningDayPresence(certainRegions: [], possibleRegions: [], homeAssumption: nil)
        }
        let possible = Set(stays.filter { $0.longestRange.contains(day) }.map(\.region))
        let certain = Set(stays.filter { $0.shortestRange.contains(day) }.map(\.region))
        let homeAssumption = homeRegion.flatMap { region in
            certain.isEmpty
                ? PlanningDayPresence.HomeAssumption(
                    region: region,
                    certainty: possible.isEmpty ? .certain : .possible,
                )
                : nil
        }
        return PlanningDayPresence(
            certainRegions: certain,
            possibleRegions: possible,
            homeAssumption: homeAssumption,
        )
    }

    public func stayIntervals(
        intersecting year: Int,
        asOf today: CalendarDay,
    ) -> [PlannedStayInterval] {
        guard let future = Self.futureRange(intersecting: year, asOf: today) else { return [] }
        return stays.compactMap { stay in
            guard let possible = Self.intersection(stay.longestRange, future) else { return nil }
            return PlannedStayInterval(
                stayID: stay.id,
                region: stay.region,
                possibleRange: possible,
                certainRange: Self.intersection(stay.shortestRange, future),
            )
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.stayID.rawValue.uuidString < $1.stayID.rawValue.uuidString
        }
    }

    /// Consecutive future gaps, split wherever the certainty of Home changes.
    public func homeIntervals(
        intersecting year: Int,
        asOf today: CalendarDay,
    ) -> [PlannedHomeInterval] {
        guard homeRegion != nil,
              let future = Self.futureRange(intersecting: year, asOf: today)
        else { return [] }
        var intervals: [PlannedHomeInterval] = []
        var current: PlannedHomeInterval?
        for day in future.lowerBound.days(through: future.upperBound) {
            let home = plannedPresence(on: day, asOf: today).homeAssumption
            if let home, let previous = current, previous.certainty == home.certainty {
                current = PlannedHomeInterval(
                    region: home.region,
                    start: previous.start,
                    end: day,
                    certainty: home.certainty,
                )
            } else {
                if let current { intervals.append(current) }
                current = home.map {
                    PlannedHomeInterval(
                        region: $0.region,
                        start: day,
                        end: day,
                        certainty: $0.certainty,
                    )
                }
            }
        }
        if let current { intervals.append(current) }
        return intervals
    }

    /// Flag any pair that can share a future day, including redundant same-region plans.
    public func overlaps(asOf today: CalendarDay) -> [PlannedStayOverlap] {
        let tomorrow = today.adding(days: 1)
        let candidates = stays.filter { $0.departure.latest >= tomorrow }.sorted {
            $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
        var result: [PlannedStayOverlap] = []
        for firstIndex in candidates.indices {
            let first = candidates[firstIndex]
            for secondIndex in (firstIndex + 1) ..< candidates.count {
                let second = candidates[secondIndex]
                guard first.id != second.id,
                      let possible = Self.intersection(first.longestRange, second.longestRange),
                      possible.upperBound >= tomorrow
                else { continue }
                let certain = Self.intersection(first.shortestRange, second.shortestRange)
                    .flatMap { range in
                        range.upperBound >= tomorrow
                            ? max(tomorrow, range.lowerBound) ... range.upperBound
                            : nil
                    }
                result.append(PlannedStayOverlap(
                    firstStayID: first.id,
                    secondStayID: second.id,
                    possibleRange: max(tomorrow, possible.lowerBound) ... possible.upperBound,
                    certainRange: certain,
                ))
            }
        }
        return result
    }

    static func futureRange(
        intersecting year: Int,
        asOf today: CalendarDay,
    ) -> ClosedRange<CalendarDay>? {
        let start = max(CalendarDay.yearRange(year).lowerBound, today.adding(days: 1))
        let end = CalendarDay.lastDay(ofYear: year)
        return start <= end ? start ... end : nil
    }

    static func intersection(
        _ first: ClosedRange<CalendarDay>,
        _ second: ClosedRange<CalendarDay>,
    ) -> ClosedRange<CalendarDay>? {
        let start = max(first.lowerBound, second.lowerBound)
        let end = min(first.upperBound, second.upperBound)
        return start <= end ? start ... end : nil
    }
}
