import Foundation
import Testing
@testable import WhereCore

struct PlannedStayRecordTests {
    @Test func newerUsesTheRevisionIdentifierToBreakTimestampTies() throws {
        let updatedAt = Date(timeIntervalSinceReferenceDate: 0)
        let stayID = PlannedStay.ID(rawValue: UUID())
        let lower = try PlannedStayRecord(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            stayID: stayID,
            value: nil,
            updatedAt: updatedAt,
        )
        let higher = try PlannedStayRecord(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            stayID: stayID,
            value: nil,
            updatedAt: updatedAt,
        )
        #expect(PlannedStayRecord.newer(higher, than: lower))
        #expect(PlannedStayRecord.newer(lower, than: higher) == false)
    }

    @Test func revisionsCannotReplaceAnotherStayIdentity() throws {
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            arrival: PlanningTestSupport.day(10, 1),
            departure: PlanningTestSupport.day(10, 3),
        )
        #expect(throws: PlannedStayRecord.ValidationError.mismatchedStayID) {
            try PlannedStayRecord(
                id: UUID(),
                stayID: .init(rawValue: UUID()),
                value: stay,
                updatedAt: PlanningTestSupport.date(PlanningTestSupport.day(9, 1)),
            )
        }
    }

    @Test func clearingRetainsStableIdentityThroughCodable() throws {
        let record = try PlannedStayRecord(
            id: UUID(),
            stayID: .init(rawValue: UUID()),
            value: nil,
            updatedAt: PlanningTestSupport.date(PlanningTestSupport.day(9, 1)),
        )
        let decoded = try JSONDecoder().decode(
            PlannedStayRecord.self,
            from: JSONEncoder().encode(record),
        )
        try decoded.validate()
        #expect(decoded == record)
        #expect(decoded.value == nil)
    }
}
