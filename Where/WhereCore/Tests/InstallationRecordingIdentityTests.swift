import Foundation
import Testing
@testable import WhereCore

struct InstallationRecordingIdentityTests {
    @Test func payloadRetainsIdentityCreationAndRegistrationWithoutConsent() throws {
        let original = InstallationRecordingIdentity(
            deviceID: RecordingDeviceID(rawValue: UUID()),
            registeredAt: Date(timeIntervalSinceReferenceDate: 1234),
            creation: .rejoin,
        )
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder()
            .decode(InstallationRecordingIdentity.self, from: data) == original)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(payload.keys) == ["deviceID", "registeredAt", "creation"])
    }
}
