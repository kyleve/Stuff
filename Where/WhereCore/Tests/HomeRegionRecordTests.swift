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
            changedByDeviceID: RecordingDeviceID(rawValue: UUID()),
        )
        let later = try HomeRegionRecord(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            region: nil,
            updatedAt: timestamp,
            changedByDeviceID: WhereCoreTestSupport.authorID,
        )

        #expect(HomeRegionRecord.newer(later, than: earlier))
        #expect(HomeRegionRecord.newer(earlier, than: later) == false)
    }

    @Test func missingAuthorOnDeletedValueFailsCurrentDecoding() throws {
        let record = try HomeRegionRecord(
            id: UUID(),
            region: nil,
            updatedAt: .now,
            changedByDeviceID: WhereCoreTestSupport.authorID,
        )
        var json = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        json.removeValue(forKey: "changedByDeviceID")
        do {
            _ = try JSONDecoder().decode(
                HomeRegionRecord.self,
                from: JSONSerialization.data(withJSONObject: json),
            )
            Issue.record("A retained deletion must name its author.")
        } catch let DecodingError.keyNotFound(key, _) {
            #expect(key.stringValue == "changedByDeviceID")
        }
    }
}
