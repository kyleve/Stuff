import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct PlannedStayTests {
    @Test func independentWindowsHaveInclusiveNestedBounds() throws {
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(10, 15),
            latestArrival: PlanningTestSupport.day(10, 17),
            departure: PlanningTestSupport.day(10, 30),
            latestDeparture: PlanningTestSupport.day(11, 4),
        )
        #expect(stay.dayCount == DayBounds(lower: 14, upper: 21))
        #expect(stay.shortestRange == PlanningTestSupport.day(10, 17) ... PlanningTestSupport.day(
            10,
            30,
        ))
        #expect(stay.longestRange == PlanningTestSupport.day(10, 15) ... PlanningTestSupport.day(
            11,
            4,
        ))
    }

    @Test func rejectsCrossedWindowsAndImpossibleDays() throws {
        #expect(throws: PlannedStay.ValidationError.reversedWindow) {
            try PlannedStay.DateWindow(
                earliest: PlanningTestSupport.day(10, 17),
                latest: PlanningTestSupport.day(10, 15),
            )
        }
        #expect(throws: PlannedStay.ValidationError.arrivalAfterDeparture) {
            try PlanningTestSupport.stay(
                region: .newYork,
                arrival: PlanningTestSupport.day(10, 15),
                latestArrival: PlanningTestSupport.day(10, 17),
                departure: PlanningTestSupport.day(10, 16),
                latestDeparture: PlanningTestSupport.day(10, 20),
            )
        }
        #expect(throws: PlannedStay.ValidationError.invalidDay) {
            try PlannedStay(
                id: .init(rawValue: UUID()),
                region: .newYork,
                arrival: .init(exact: PlanningTestSupport.day(2, 30)),
                departure: .init(exact: PlanningTestSupport.day(3, 1)),
            )
        }
    }

    @Test func rejectsUnsupportedDestinations() throws {
        let unknown = try JSONDecoder().decode(Region.self, from: Data("\"unknown-region\"".utf8))
        for region in [Region.other, unknown] {
            #expect(throws: PlannedStay.ValidationError.unsupportedRegion) {
                try PlanningTestSupport.stay(
                    region: region,
                    arrival: PlanningTestSupport.day(10, 15),
                    departure: PlanningTestSupport.day(10, 15),
                )
            }
        }
    }

    @Test func currentWireShapeUsesStableUUIDAndExplicitWindowFields() throws {
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(10, 15),
            departure: PlanningTestSupport.day(10, 15),
        )
        let data = try JSONEncoder().encode(stay)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["id"] as? String == stay.id.rawValue.uuidString)
        let arrival = try #require(object["arrival"] as? [String: Any])
        #expect(Set(arrival.keys) == ["earliest", "latest"])
        let decoded = try JSONDecoder().decode(PlannedStay.self, from: data)
        try decoded.validate()
        #expect(decoded == stay)
        #expect(stay.dayCount == DayBounds(exact: 1))
        #expect(stay.arrival.isExact)
    }
}
