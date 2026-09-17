import Foundation
import Testing
@testable import WhereCore

struct HomeRegionRecordTests {
    @Test func newerUsesRevisionIdentityToBreakTimestampTies() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = try HomeRegionRecord(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            region: .california,
            updatedAt: timestamp,
        )
        let later = try HomeRegionRecord(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            region: nil,
            updatedAt: timestamp,
        )

        #expect(HomeRegionRecord.newer(later, than: earlier))
        #expect(HomeRegionRecord.newer(earlier, than: later) == false)
    }
}
