import Foundation
import RegionKit

/// A contiguous run of assumed Home days with one certainty level.
public struct PlannedHomeInterval: Hashable, Sendable, Identifiable {
    public let region: Region
    public let start: CalendarDay
    public let end: CalendarDay
    public let certainty: PlanningCertainty

    public var id: Self {
        self
    }

    public var dayCount: DayBounds {
        let count = start.days(through: end).count
        return DayBounds(lower: certainty == .certain ? count : 0, upper: count)
    }
}
