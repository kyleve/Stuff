import Foundation
import Testing
@testable import WhereCore

struct RecordingDeviceProfileTests {
    @Test func canonicalOrderingIncludesUnknownPlatformDetail() {
        let deviceID = RecordingDeviceID(rawValue: UUID())
        let registeredAt = Date(timeIntervalSinceReferenceDate: 100)
        let winner = RecordingDeviceProfile(
            id: deviceID,
            systemName: "Other Device",
            kind: .other("spatial-computer"),
            registeredAt: registeredAt,
            registrationGenerationID: .initial,
        )
        let duplicate = RecordingDeviceProfile(
            id: deviceID,
            systemName: "Other Device",
            kind: .other("television"),
            registeredAt: registeredAt,
            registrationGenerationID: .initial,
        )

        #expect(RecordingDeviceProfile.isCanonicalBefore(winner, duplicate))
        #expect(!RecordingDeviceProfile.isCanonicalBefore(duplicate, winner))
    }
}
