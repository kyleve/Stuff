import Foundation
import RegionKit

/// A derived gap between saved stays, with one Home certainty level.
/// It has no persisted stay identity or editable endpoints: changing the itinerary
/// recomputes these intervals, while explicit stays retain their own identities.
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
