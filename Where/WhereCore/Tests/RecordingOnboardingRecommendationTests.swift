import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingOnboardingRecommendationTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 100_000)
    private static let otherID = RecordingDeviceID(rawValue: UUID())

    @Test(arguments: [RecordingDeviceStatus.recording, .permissionRequired, .off, .unknown])
    func anotherDeviceNeverSuppressesThePhoneDefault(status: RecordingDeviceStatus) {
        let other = device(deviceID: Self.otherID, status: status, removedAt: nil)
        let recommendation = RecordingOnboardingRecommendation(
            for: installation(kind: .phone, isRejoining: false),
            devices: [other],
        )
        #expect(recommendation.isEnabled)
        #expect(recommendation.existingDevices == [other])
    }

    @Test func replacementCandidatesExcludeCurrentAndRemovedDevices() {
        let context = installation(kind: .phone, isRejoining: false)
        let recommendation = RecordingOnboardingRecommendation(
            for: context,
            devices: [
                device(deviceID: context.currentDevice.id, status: .recording, removedAt: nil),
                device(deviceID: Self.otherID, status: .recording, removedAt: Self.now),
            ],
        )
        #expect(recommendation.existingDevices.isEmpty)
    }

    @Test func rejoinDefaultsOffEvenForAPhone() {
        #expect(!RecordingOnboardingRecommendation(
            for: installation(kind: .phone, isRejoining: true),
            devices: [],
        ).isEnabled)
    }

    @Test(arguments: [RecordingDeviceKind.tablet, .computer, .other(nil)])
    func nonPhoneDefaultsOff(kind: RecordingDeviceKind) {
        #expect(!RecordingOnboardingRecommendation(
            for: installation(kind: kind, isRejoining: false),
            devices: [],
        ).isEnabled)
    }

    private func installation(
        kind: RecordingDeviceKind,
        isRejoining: Bool,
    ) -> InstallationRecordingContext {
        InstallationRecordingContext(
            currentDevice: CurrentRecordingDevice(
                id: InstallationRecordingContext.testing.currentDevice.id,
                systemName: "Current",
                kind: kind,
            ),
            registeredAt: Self.now,
            recordingChoice: .unconfirmed,
            isRejoining: isRejoining,
        )
    }

    private func device(
        deviceID: RecordingDeviceID,
        status: RecordingDeviceStatus,
        removedAt: Date?,
    ) -> RecordingDevice {
        RecordingDevice(
            id: deviceID,
            systemName: "Other iPhone",
            nickname: nil,
            kind: .phone,
            registeredAt: Self.now.addingTimeInterval(-100_000),
            lastSeenAt: Self.now,
            removedAt: removedAt,
            status: status,
        )
    }
}
