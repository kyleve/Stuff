import Testing
@testable import WhereCore

struct PlannedStayOverlapTests {
    @Test func flagsPossibleSharedDatesWithoutClaimingTheyAreCertain() throws {
        let first = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(10, 15),
            latestArrival: PlanningTestSupport.day(10, 17),
            departure: PlanningTestSupport.day(10, 30),
            latestDeparture: PlanningTestSupport.day(11, 4),
        )
        let second = try PlanningTestSupport.stay(
            region: .california,
            arrival: PlanningTestSupport.day(11, 1),
            latestArrival: PlanningTestSupport.day(11, 3),
            departure: PlanningTestSupport.day(11, 5),
            latestDeparture: PlanningTestSupport.day(11, 8),
        )
        let planning = PlanningSnapshot(stays: [first, second], homeRegion: nil)
        let overlap = try #require(planning.overlaps(asOf: PlanningTestSupport.day(9, 13)).first)
        #expect(Set([overlap.firstStayID, overlap.secondStayID]) == [first.id, second.id])
        #expect(overlap.possibleRange == PlanningTestSupport.day(11, 1) ... PlanningTestSupport.day(
            11,
            4,
        ))
        #expect(overlap.certainRange == nil)
        #expect(planning.overlaps(asOf: PlanningTestSupport.day(11, 8)).isEmpty)
    }

    @Test func keepsSameRegionOverlapVisibleAndClipsPastSharedDays() throws {
        let first = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(10, 1),
            departure: PlanningTestSupport.day(10, 10),
        )
        let second = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(10, 5),
            departure: PlanningTestSupport.day(10, 15),
        )
        let overlap = try #require(PlanningSnapshot(stays: [first, second], homeRegion: nil)
            .overlaps(asOf: PlanningTestSupport.day(10, 7)).first)
        #expect(overlap.possibleRange == PlanningTestSupport.day(10, 8) ... PlanningTestSupport.day(
            10,
            10,
        ))
        #expect(overlap.certainRange == overlap.possibleRange)
    }
}
