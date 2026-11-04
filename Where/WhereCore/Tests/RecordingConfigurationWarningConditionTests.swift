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

    struct OtherDeviceCase {
        let elapsed: TimeInterval
        let status: RecordingDeviceStatus
        let isRemoved: Bool
        let isCurrent: Bool
        let expected: Bool
    }

    @Test(arguments: [
        OtherDeviceCase(
            elapsed: 86400,
            status: .recording,
            isRemoved: false,
            isCurrent: false,
            expected: false,
        ),
        OtherDeviceCase(
            elapsed: 86401,
            status: .recording,
            isRemoved: false,
            isCurrent: false,
            expected: true,
        ),
        OtherDeviceCase(
            elapsed: 0,
            status: .permissionRequired,
            isRemoved: false,
            isCurrent: false,
            expected: false,
        ),
        OtherDeviceCase(
            elapsed: 0,
            status: .off,
            isRemoved: false,
            isCurrent: false,
            expected: true,
        ),
        OtherDeviceCase(
            elapsed: 0,
            status: .recording,
            isRemoved: true,
            isCurrent: false,
            expected: true,
        ),
        OtherDeviceCase(
            elapsed: 0,
            status: .recording,
            isRemoved: false,
            isCurrent: true,
            expected: true,
        ),
    ])
    func onlyRecentActiveOtherRecordersSuppressWarning(testCase: OtherDeviceCase) {
        let device = RecordingDevice(
            id: testCase.isCurrent ? Self.currentDevice.id : RecordingDeviceID(rawValue: UUID()),
            systemName: "iPhone",
            nickname: nil,
            kind: .phone,
            registeredAt: Self.now.addingTimeInterval(-100_000),
            lastSeenAt: Self.now.addingTimeInterval(-testCase.elapsed),
            removedAt: testCase.isRemoved ? Self.now : nil,
            status: testCase.status,
        )
        let condition = RecordingConfigurationWarningCondition(
            currentDevice: Self.currentDevice,
            devices: [device],
            automaticRecordingEnabled: false,
            authorizationStatus: .whenInUse,
            now: Self.now,
        )

        #expect(condition.isActive == testCase.expected)
    }
}
