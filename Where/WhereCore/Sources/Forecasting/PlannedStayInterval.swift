import Foundation
import RegionKit

/// One plan clipped to a displayed year's future. The original stay remains editable by ID.
public struct PlannedStayInterval: Hashable, Sendable, Identifiable {
    public let stayID: PlannedStay.ID
    public let region: Region
    public let possibleRange: ClosedRange<CalendarDay>
    public let certainRange: ClosedRange<CalendarDay>?

    public var id: PlannedStay.ID {
        stayID
    }

    public var start: CalendarDay {
        possibleRange.lowerBound
    }

    public var end: CalendarDay {
        possibleRange.upperBound
    }

    public var dayCount: DayBounds {
        DayBounds(
            lower: certainRange.map { $0.lowerBound.days(through: $0.upperBound).count } ?? 0,
            upper: start.days(through: end).count,
        )
    }
}
