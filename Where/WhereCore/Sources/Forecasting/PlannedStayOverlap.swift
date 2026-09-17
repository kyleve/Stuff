import Foundation

/// Independent plans that can share a day; a nil certain range means the overlap is optional.
public struct PlannedStayOverlap: Hashable, Sendable {
    public let firstStayID: PlannedStay.ID
    public let secondStayID: PlannedStay.ID
    public let possibleRange: ClosedRange<CalendarDay>
    public let certainRange: ClosedRange<CalendarDay>?
}
