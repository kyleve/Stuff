import Foundation
import Testing
import WhereCore
@testable import WhereUI

struct PlanningTimelineItemTests {
    @Test func joinsOnlyCertainAdjacentPresenceInTheSameRegion() throws {
        let today = PlanningModelTestSupport.today
        let calendar = PlanningModelTestSupport.calendar
        let stint = RegionStint(
            region: .newYork,
            start: today.startOfDay(in: calendar),
            end: today.startOfDay(in: calendar),
            dayCount: 1,
        )
        let stay = try PlannedStay(
            id: .init(rawValue: UUID()),
            region: .newYork,
            arrival: .init(exact: today.adding(days: 1)),
            departure: .init(exact: today.adding(days: 7)),
        )
        let items = PlanningTimelineItem.items(
            planning: .init(stays: [stay], homeRegion: nil),
            year: 2026,
            today: today,
        )
        let item = try #require(items.first)
        #expect(item.continues(stint, calendar: calendar))
        let otherRegion = RegionStint(
            region: .california,
            start: stint.start,
            end: stint.end,
            dayCount: 1,
        )
        #expect(!item.continues(otherRegion, calendar: calendar))
        let gap = RegionStint(
            region: .newYork,
            start: stint.start,
            end: today.adding(days: -1).startOfDay(in: calendar),
            dayCount: 1,
        )
        #expect(!item.continues(gap, calendar: calendar))
        let flexible = try PlannedStay(
            id: stay.id,
            region: stay.region,
            arrival: .init(
                earliest: today.adding(days: 1),
                latest: today.adding(days: 2),
            ),
            departure: stay.departure,
        )
        let uncertain = try #require(PlanningTimelineItem.items(
            planning: .init(stays: [flexible], homeRegion: nil),
            year: 2026,
            today: today,
        ).first)
        #expect(!uncertain.continues(stint, calendar: calendar))
    }

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
