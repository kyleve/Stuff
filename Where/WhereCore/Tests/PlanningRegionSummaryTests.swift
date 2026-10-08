import RegionKit
import Testing
@testable import WhereCore

struct PlanningRegionSummaryTests {
    @Test func unionsOverlappingAndDuplicatePlansAndExcludesTodayFromHomeGaps() throws {
        let today = PlanningTestSupport.day(12, 25)
        let uncertain = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: today,
            latestArrival: PlanningTestSupport.day(12, 27),
            departure: PlanningTestSupport.day(12, 28),
            latestDeparture: PlanningTestSupport.day(12, 30),
        )
        let exact = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(12, 28),
            departure: PlanningTestSupport.day(12, 29),
        )
        let summaries = PlanningSnapshot(
            stays: [uncertain, uncertain, exact],
            homeRegion: .california,
        )
        .regionSummaries(
            in: PlanningTestSupport.day(12, 24) ... PlanningTestSupport.day(12, 31),
            asOf: today,
        )
        #expect(summaries.map(\.region) == Region.inCanonicalOrder([.newYork, .california]))
        let ny = try #require(summaries.first { $0.region == .newYork })
        let ca = try #require(summaries.first { $0.region == .california })
        #expect(ny.plannedDays == DayBounds(lower: 3, upper: 5))
        #expect(ny.homeDays == DayBounds(exact: 0))
        #expect(ca.plannedDays == DayBounds(exact: 0))
        #expect(ca.homeDays == DayBounds(lower: 1, upper: 3))
    }

    @Test func retainsRawHomeAndExplicitBoundsWhenEffectivePresenceIsCertain() throws {
        let today = PlanningTestSupport.day(12, 25)
        let stay = try PlanningTestSupport.stay(
            region: .california,
            arrival: PlanningTestSupport.day(12, 28),
            latestArrival: PlanningTestSupport.day(12, 29),
            departure: PlanningTestSupport.day(12, 30),
            latestDeparture: PlanningTestSupport.day(12, 31),
        )
        let summary = try #require(PlanningSnapshot(stays: [stay], homeRegion: .california)
            .regionSummaries(in: today ... PlanningTestSupport.day(12, 31), asOf: today).first)
        #expect(summary.plannedDays == DayBounds(lower: 2, upper: 4))
        #expect(summary.homeDays == DayBounds(lower: 2, upper: 4))
    }

    @Test func omitsEmptyRegionsAndHistoricalRanges() {
        let today = PlanningTestSupport.day(12, 25)
        #expect(PlanningSnapshot(stays: [], homeRegion: nil)
            .regionSummaries(in: today ... PlanningTestSupport.day(12, 31), asOf: today).isEmpty)
        #expect(PlanningSnapshot(stays: [], homeRegion: .california)
            .regionSummaries(in: PlanningTestSupport.day(12, 1) ... today, asOf: today).isEmpty)
    }
}
