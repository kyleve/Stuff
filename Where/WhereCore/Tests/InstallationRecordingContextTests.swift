import Foundation
import Testing
@testable import WhereCore

struct InstallationRecordingContextTests {
    @Test func renewedConsentDoesNotReuseTheIdentityRegistrationTime() {
        let proposed = context(kind: .phone)
        let confirmation = Self.registeredAt.addingTimeInterval(30 * 24 * 3600)
        let confirmed = proposed.confirmingInitialRecording(isEnabled: true, at: confirmation)
        #expect(confirmed.currentDevice.id == proposed.currentDevice.id)
        #expect(confirmed.registeredAt == proposed.registeredAt)
        #expect(confirmed.recordingEnabledAt == confirmation)
    }

    @Test func recommendationComesFromTheDeviceKind() {
        let phone = context(kind: .phone)
        let tablet = context(kind: .tablet)

        #expect(phone.recommendedRecordingEnabled)
        #expect(tablet.recommendedRecordingEnabled == false)
    }

    @Test func confirmedConsentStaysPendingUntilSetupCompletes() {
        let confirmed = context(kind: .phone).confirmingInitialRecording(
            isEnabled: false,
            at: Self.registeredAt,
        )
        #expect(!confirmed.hasCompletedSetup)
        #expect(!confirmed.settingAutomaticRecordingEnabled(true, at: Self.registeredAt)
            .hasCompletedSetup)
        let completed = confirmed.completingSetup()
        #expect(completed.hasCompletedSetup)
        #expect(completed.settingAutomaticRecordingEnabled(true, at: Self.registeredAt)
            .hasCompletedSetup)
    }

    @Test func confirmationAndLaterSettingsChangePreserveIdentity() {
        let proposed = context(kind: .tablet)
        let confirmed = proposed.confirmingInitialRecording(isEnabled: false, at: Self.registeredAt)
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
