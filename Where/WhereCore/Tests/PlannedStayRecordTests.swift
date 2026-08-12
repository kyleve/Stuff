import Foundation
import Testing
@testable import WhereCore

struct PlannedStayRecordTests {
    @Test func newerUsesTheIdentifierToBreakTimestampTies() throws {
        let updatedAt = Date(timeIntervalSinceReferenceDate: 0)
        let lower = try PlannedStayRecord(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            value: nil,
            updatedAt: updatedAt,
        )
        let higher = try PlannedStayRecord(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            value: nil,
            updatedAt: updatedAt,
        )

        #expect(PlannedStayRecord.newer(higher, than: lower))
        #expect(!PlannedStayRecord.newer(lower, than: higher))
    }
}
