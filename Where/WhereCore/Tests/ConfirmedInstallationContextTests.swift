import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct ConfirmedInstallationContextTests {
    @Test func repeatedConfirmationRetainsTheExistingConsentIntervalAndControl() throws {
        let original = ConfirmedInstallationContext.testing
            .settingRecordingAccount(.invalidated(.cloudKit(recordName: "account-a")))
        let confirmed = original.context.confirmingInitialRecording(isEnabled: false)
        #expect(confirmed == original)
        #expect(try confirmed.context.confirmed() == original)
    }

    @Test func settingsRetainsAnOnIntervalAndStartsANewOneAfterOff() {
        let original = ConfirmedInstallationContext.testing
            .settingRecordingAccount(.invalidated(.cloudKit(recordName: "account-a")))
        let later = original.registeredAt.addingTimeInterval(500)
        #expect(original.settingAutomaticRecordingEnabled(true, at: later) == original)
        let off = original.settingAutomaticRecordingEnabled(false, at: later)
        #expect(off.recordingChoice == .off)
        let on = off.settingAutomaticRecordingEnabled(true, at: later)
        #expect(on.recordingChoice == .on(enabledAt: later))
        #expect(on.currentDevice == original.currentDevice)
        #expect(on.recordingControl == original.recordingControl)
    }

    @Test func aRestoredInstallationCannotSupplyConfirmedServices() {
        let context = InstallationRecordingContext(
            currentDevice: InstallationRecordingContext.testing.currentDevice,
            registeredAt: Date(),
            recordingChoice: .unconfirmed,
            isRejoining: false,
        )
        #expect(throws: DataCompatibilityError.recordingChoiceRequired) { try context.confirmed() }
    }
}
