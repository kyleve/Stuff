import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingConfigurationWarningConditionTests {
    struct LocalCase {
        let automaticRecordingEnabled: Bool?
        let authorizationStatus: LocationAuthorizationStatus
        let expected: Bool
    }

    private static let now = Date(timeIntervalSinceReferenceDate: 100_000)
    private static let currentDevice = InstallationRecordingContext.testing.currentDevice

    @Test(arguments: [
        LocalCase(
            automaticRecordingEnabled: false,
            authorizationStatus: .whenInUse,
            expected: true,
        ),
        LocalCase(
            automaticRecordingEnabled: true,
            authorizationStatus: .whenInUse,
            expected: false,
        ),
        LocalCase(
            automaticRecordingEnabled: false,
            authorizationStatus: .always,
            expected: false,
        ),
        LocalCase(
            automaticRecordingEnabled: nil,
            authorizationStatus: .whenInUse,
            expected: false,
        ),
    ])
    func combinesLocalRecordingAndAuthorizationRequirements(localCase: LocalCase) {
        let condition = RecordingConfigurationWarningCondition(
            currentDevice: Self.currentDevice,
            devices: [],
            automaticRecordingEnabled: localCase.automaticRecordingEnabled,
            authorizationStatus: localCase.authorizationStatus,
            now: Self.now,
        )

        #expect(condition.isActive == localCase.expected)
    }

    @Test func recentRecorderMakesThisPhoneSecondary() {
        let otherDevice = RecordingDevice(
            id: RecordingDeviceID(rawValue: UUID()),
            systemName: "Other iPhone",
            nickname: nil,
            kind: .phone,
            registeredAt: Self.now.addingTimeInterval(-100_000),
            lastSeenAt: Self.now,
            removedAt: nil,
            status: .recording,
        )

        let condition = RecordingConfigurationWarningCondition(
            currentDevice: Self.currentDevice,
            devices: [otherDevice],
            automaticRecordingEnabled: false,
            authorizationStatus: .whenInUse,
            now: Self.now,
        )

        #expect(condition.isActive == false)
    }
}
