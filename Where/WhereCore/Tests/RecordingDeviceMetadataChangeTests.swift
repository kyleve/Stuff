import Foundation
import Testing
@testable import WhereCore

struct RecordingDeviceMetadataChangeTests {
    private static let deviceID = RecordingDeviceID(
        rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    )
    private static let changeID = UUID(
        uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
    )!

    @Test func clearedNicknameRoundTripsAsANicknameEvent() throws {
        let change = RecordingDeviceMetadataChange(
            id: Self.changeID,
            deviceID: Self.deviceID,
            revision: 1,
            changedAt: Date(timeIntervalSinceReferenceDate: 100),
            changedByDeviceID: Self.deviceID,
            payload: .nickname(nil),
        )

        let decoded = try JSONDecoder().decode(
            RecordingDeviceMetadataChange.self,
            from: JSONEncoder().encode(change),
        )

        #expect(decoded == change)
        #expect(decoded.field == .nickname)
        #expect(decoded.nickname == nil)
    }

    @Test func decoderRejectsTheRetiredArchiveMetadataField() throws {
        let change = RecordingDeviceMetadataChange(
            id: Self.changeID,
            deviceID: Self.deviceID,
            revision: 0,
            changedAt: Date(timeIntervalSinceReferenceDate: 100),
            changedByDeviceID: Self.deviceID,
            payload: .nickname(nil),
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(change)) as? [String: Any],
        )
        var payload = try #require(object["payload"] as? [String: Any])
        payload["field"] = "archive"
        payload["isArchived"] = true
        object["payload"] = payload
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RecordingDeviceMetadataChange.self, from: data)
        }
    }
}
