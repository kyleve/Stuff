import Testing
@testable import WhereCore

struct PlannedHomeIntervalTests {
    @Test func groupsHomeGapsAndSplitsAtUncertainTripEdges() throws {
        let today = PlanningTestSupport.day(12, 25)
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(12, 28),
            latestArrival: PlanningTestSupport.day(12, 29),
            departure: PlanningTestSupport.day(12, 30),
            latestDeparture: PlanningTestSupport.day(12, 31),
        )
        let intervals = PlanningSnapshot(stays: [stay], homeRegion: .california)
            .homeIntervals(intersecting: 2026, asOf: today)
        try #require(intervals.count == 3)
        #expect(intervals[0].start == PlanningTestSupport.day(12, 26))
        #expect(intervals[0].end == PlanningTestSupport.day(12, 27))
        #expect(intervals[0].certainty == .certain)
        #expect(intervals[0].dayCount == DayBounds(exact: 2))
        #expect(intervals[1].start == PlanningTestSupport.day(12, 28))
        #expect(intervals[1].certainty == .possible)
        #expect(intervals[1].dayCount == DayBounds(lower: 0, upper: 1))
        #expect(intervals[2].start == PlanningTestSupport.day(12, 31))
        #expect(intervals[2].dayCount == DayBounds(lower: 0, upper: 1))
    }
}
