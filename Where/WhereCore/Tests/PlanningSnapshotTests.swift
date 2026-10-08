import RegionKit
import Testing
@testable import WhereCore

struct PlanningSnapshotTests {
    @Test func projectionsNeverFillTodayOrHistoricalGaps() throws {
        let today = PlanningTestSupport.day(9, 13)
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(9, 1),
            departure: PlanningTestSupport.day(9, 20),
        )
        let planning = PlanningSnapshot(stays: [stay], homeRegion: .california)
        for day in [today.adding(days: -1), today] {
            let presence = planning.plannedPresence(on: day, asOf: today)
            #expect(presence.possibleRegions.isEmpty)
            #expect(presence.certainRegions.isEmpty)
            #expect(presence.homeAssumption == nil)
        }
        #expect(planning.plannedPresence(on: today.adding(days: 1), asOf: today)
            .membership(in: .newYork) == .planned(.certain))
    }

    @Test func historicalPolicyLeavesFutureGapsUnassigned() {
        let today = PlanningTestSupport.day(9, 13)
        let planning = PlanningSnapshot(stays: [], homeRegion: nil)
        #expect(planning.plannedPresence(on: today.adding(days: 1), asOf: today)
            .homeAssumption == nil)
        #expect(planning.homeIntervals(intersecting: 2026, asOf: today).isEmpty)
    }

    @Test func completedPlansRemainStoredButDoNotProject() throws {
        let today = PlanningTestSupport.day(9, 13)
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(8, 1),
            departure: PlanningTestSupport.day(8, 20),
        )
        let planning = PlanningSnapshot(stays: [stay], homeRegion: .california)
        #expect(planning.stays == [stay])
        #expect(planning.stayIntervals(intersecting: 2026, asOf: today).isEmpty)
        #expect(planning.overlaps(asOf: today).isEmpty)
    }
}
