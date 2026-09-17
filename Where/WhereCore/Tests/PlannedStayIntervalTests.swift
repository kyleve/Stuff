import Testing
@testable import WhereCore

struct PlannedStayIntervalTests {
    @Test func clipsThePossibleEnvelopeAndCertainCoreIndependently() throws {
        let today = PlanningTestSupport.day(12, 29)
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(12, 30),
            latestArrival: PlanningTestSupport.day(1, 2, year: 2027),
            departure: PlanningTestSupport.day(1, 5, year: 2027),
            latestDeparture: PlanningTestSupport.day(1, 8, year: 2027),
        )
        let planning = PlanningSnapshot(stays: [stay], homeRegion: nil)
        let thisYear = try #require(planning.stayIntervals(intersecting: 2026, asOf: today).first)
        #expect(thisYear.stayID == stay.id)
        #expect(thisYear.start == PlanningTestSupport.day(12, 30))
        #expect(thisYear.end == PlanningTestSupport.day(12, 31))
        #expect(thisYear.dayCount == DayBounds(lower: 0, upper: 2))
        #expect(thisYear.certainRange == nil)
        let nextYear = try #require(planning.stayIntervals(intersecting: 2027, asOf: today).first)
        #expect(nextYear.dayCount == DayBounds(lower: 4, upper: 8))
        #expect(planning.stayIntervals(intersecting: 2025, asOf: today).isEmpty)
    }

    @Test func clipsAnOngoingStayAfterTodayWithoutMovingItsStoredDates() throws {
        let today = PlanningTestSupport.day(9, 13)
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(9, 1),
            latestArrival: PlanningTestSupport.day(9, 10),
            departure: PlanningTestSupport.day(9, 20),
            latestDeparture: PlanningTestSupport.day(9, 25),
        )
        let interval = try #require(PlanningSnapshot(stays: [stay], homeRegion: nil)
            .stayIntervals(intersecting: 2026, asOf: today).first)
        #expect(interval.start == PlanningTestSupport.day(9, 14))
        #expect(interval.dayCount == DayBounds(lower: 7, upper: 12))
        #expect(stay.arrival.earliest == PlanningTestSupport.day(9, 1))
    }
}
