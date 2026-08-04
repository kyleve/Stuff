import Foundation
import Testing
@testable import WhereCore

struct InstallationRecordingContextTests {
    @Test func recommendationComesFromTheDeviceKind() {
        let phone = context(kind: .phone)
        let tablet = context(kind: .tablet)

        #expect(phone.recommendedRecordingEnabled)
        #expect(tablet.recommendedRecordingEnabled == false)
    }

    @Test func confirmationAndLaterSettingsChangePreserveIdentity() {
        let proposed = context(kind: .tablet)
        let confirmed = proposed.confirmingInitialRecording(isEnabled: false)
        let enabledAt = Self.registeredAt.addingTimeInterval(100)
        let updated = confirmed.settingAutomaticRecordingEnabled(true, at: enabledAt)

        #expect(updated.currentDevice == proposed.currentDevice)
        #expect(updated.registeredAt == proposed.registeredAt)
        #expect(confirmed.automaticRecordingEnabled == false)
        #expect(updated.automaticRecordingEnabled == true)
        #expect(updated.recordingEnabledAt == enabledAt)
    }

    private func context(kind: RecordingDeviceKind) -> InstallationRecordingContext {
        InstallationRecordingContext(
            currentDevice: CurrentRecordingDevice(
                id: RecordingDeviceID(rawValue: UUID()),
                systemName: kind == .tablet ? "iPad" : "iPhone",
                kind: kind,
            ),
            registeredAt: Self.registeredAt,
            recordingChoice: .unconfirmed,
            isRejoining: false,
        )
    }

    private static let registeredAt = Date(timeIntervalSinceReferenceDate: 100)
}
