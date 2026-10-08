import RegionKit
import Testing
@testable import WhereCore

struct PlanningDayPresenceTests {
    @Test func distinguishesCertainPlansPossiblePlansAndHomeAssumptions() throws {
        let today = PlanningTestSupport.day(12, 25)
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(12, 28),
            latestArrival: PlanningTestSupport.day(12, 29),
            departure: PlanningTestSupport.day(12, 30),
            latestDeparture: PlanningTestSupport.day(12, 31),
        )
        let planning = PlanningSnapshot(stays: [stay], homeRegion: .california)
        let gap = planning.plannedPresence(on: PlanningTestSupport.day(12, 27), asOf: today)
        #expect(gap.membership(in: .newYork) == nil)
        #expect(gap.membership(in: .california) == .homeAssumed(.certain))
        let possible = planning.plannedPresence(on: PlanningTestSupport.day(12, 28), asOf: today)
        #expect(possible.membership(in: .newYork) == .planned(.possible))
        #expect(possible.membership(in: .california) == .homeAssumed(.possible))
        let certain = planning.plannedPresence(on: PlanningTestSupport.day(12, 29), asOf: today)
        #expect(certain.membership(in: .newYork) == .planned(.certain))
        #expect(certain.membership(in: .california) == nil)
    }

    @Test func homePlanPreservesExplicitAndAssumedProvenanceSeparately() throws {
        let today = PlanningTestSupport.day(12, 25)
        let stay = try PlanningTestSupport.stay(
            region: .california,
            arrival: PlanningTestSupport.day(12, 28),
            latestArrival: PlanningTestSupport.day(12, 29),
            departure: PlanningTestSupport.day(12, 30),
        )
        let planning = PlanningSnapshot(stays: [stay], homeRegion: .california)
        let presence = planning.plannedPresence(on: PlanningTestSupport.day(12, 28), asOf: today)
        // CA is present in every scenario. Raw fields retain the uncertain
        // explicit plan and alternative assumption without weakening effective coverage.
        #expect(presence.membership(in: .california) == .homeAssumed(.certain))
        #expect(presence.certainRegions.isEmpty)
        #expect(presence.possibleRegions == [.california])
        #expect(presence.homeAssumption?.region == .california)
        #expect(presence.homeAssumption?.certainty == .possible)
    }

    @Test func anotherPossibleDestinationKeepsHomePresenceUncertain() throws {
        let today = PlanningTestSupport.day(12, 25)
        let stays = try [Region.california, .newYork].map { region in
            try PlanningTestSupport.stay(
                region: region,
                arrival: PlanningTestSupport.day(12, 28),
                latestArrival: PlanningTestSupport.day(12, 29),
                departure: PlanningTestSupport.day(12, 30),
            )
        }
        let presence = PlanningSnapshot(stays: stays, homeRegion: .california)
            .plannedPresence(on: PlanningTestSupport.day(12, 28), asOf: today)
        #expect(presence.membership(in: .california) == .planned(.possible))
        #expect(presence.membership(in: .newYork) == .planned(.possible))
        #expect(presence.homeAssumption?.certainty == .possible)
    }
}
