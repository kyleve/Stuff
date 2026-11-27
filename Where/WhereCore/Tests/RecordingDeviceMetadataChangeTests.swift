import Foundation
import Testing
@testable import WhereCore

struct RecordingDeviceMetadataChangeTests {
    private static let deviceID = RecordingDeviceID(
        rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    )
    private static let changeID = RecordingDeviceMetadataChange.ID(
        rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
    )

    private static let profile = RecordingDeviceProfile(
        id: .init(rawValue: UUID(uuidString: "65000000-0000-0000-0000-000000000001")!),
        systemName: "iPhone",
        kind: .phone,
        registeredAt: Date(timeIntervalSinceReferenceDate: 100),
        registrationGenerationID: .initial,
    )

    @Test func hardwareFactUsesThePortableModelEventIdentity() throws {
        let change = RecordingDeviceMetadataChange.hardwareModelIdentifier(
            "iPhone16,1",
            for: Self.profile,
        )
        #expect(change.id.rawValue.uuidString == "64347FF5-9708-8B3B-AB2C-B2043FE0FF4F")
        #expect(change.revision == 0)
        #expect(change.changedAt == Self.profile.registeredAt)
        #expect(change.changedByDeviceID == Self.profile.id)
        let data = try JSONEncoder().encode(change)
        #expect(try JSONDecoder().decode(RecordingDeviceMetadataChange.self, from: data) == change)
    }

    @Test(arguments: ["whitespace", "eventID", "revision", "author"])
    func decoderRejectsMalformedHardwareFacts(fault: String) throws {
        let change = RecordingDeviceMetadataChange.hardwareModelIdentifier(
            "iPhone16,1",
            for: Self.profile,
        )
        var manifest = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(change)) as? [String: Any])
        switch fault {
            case "whitespace": manifest["payload"] = [
                    "field": "hardwareModelIdentifier",
                    "hardwareModelIdentifier": "   ",
                ]
            case "eventID": manifest["id"] = UUID().uuidString
            case "revision": manifest["revision"] = 1
            default: manifest["changedByDeviceID"] = Self.deviceID.storeURL.absoluteString
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                RecordingDeviceMetadataChange.self,
                from: JSONSerialization.data(withJSONObject: manifest),
            )
        }
    }

    @Test(arguments: ["nickname", "hardwareModelIdentifier"])
    func decoderRejectsASecondMetadataValue(field: String) throws {
        let payload = [
            "field": field,
            "hardwareModelIdentifier": "iPhone16,1",
            "nickname": "Travel Phone",
        ]
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                RecordingDeviceMetadataPayload.self,
                from: JSONEncoder().encode(payload),
            )
        }
    }

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
