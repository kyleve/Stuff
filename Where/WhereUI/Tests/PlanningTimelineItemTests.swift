import Foundation
import Testing
import WhereCore
@testable import WhereUI

struct PlanningTimelineItemTests {
    @Test func interleavesHomeGapsAndKeepsSeparateStayIdentities() throws {
        let today = CalendarDay(year: 2026, month: 12, day: 20)
        let first = try PlannedStay(
            id: .init(rawValue: UUID()),
            region: .newYork,
            arrival: .init(exact: today.adding(days: 3)),
            departure: .init(exact: today.adding(days: 4)),
        )
        let second = try PlannedStay(
            id: .init(rawValue: UUID()),
            region: .newYork,
            arrival: .init(exact: today.adding(days: 4)),
            departure: .init(exact: today.adding(days: 5)),
        )
        let items = PlanningTimelineItem.items(
            planning: .init(stays: [second, first], homeRegion: .california),
            year: 2026,
            today: today,
        )
        #expect(items.map(\.start) == [
            today.adding(days: 1),
            first.arrival.earliest,
            second.arrival.earliest,
            today.adding(days: 6),
        ])
        #expect(items[1].id == .stay(first.id))
        #expect(items[2].id == .stay(second.id))
        #expect(items.first?.membership == .homeAssumed(.certain))
    }
}
