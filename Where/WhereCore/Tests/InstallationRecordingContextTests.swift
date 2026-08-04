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
        let updated = confirmed.settingAutomaticRecordingEnabled(true)

        #expect(updated.currentDevice == proposed.currentDevice)
        #expect(updated.registeredAt == proposed.registeredAt)
        #expect(confirmed.automaticRecordingEnabled == false)
        #expect(updated.automaticRecordingEnabled == true)
    }

    private func context(kind: RecordingDeviceKind) -> InstallationRecordingContext {
        InstallationRecordingContext(
            currentDevice: CurrentRecordingDevice(
                id: RecordingDeviceID(rawValue: UUID()),
                systemName: kind == .tablet ? "iPad" : "iPhone",
                kind: kind,
            ),
            registeredAt: Self.registeredAt,
            automaticRecordingEnabled: nil,
            isRejoining: false,
        )
    }

    private static let registeredAt = Date(timeIntervalSinceReferenceDate: 100)
}
