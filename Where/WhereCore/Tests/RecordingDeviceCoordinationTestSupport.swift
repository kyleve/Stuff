import Foundation
@testable import WhereCore

@MainActor
final class RecordingCoordinationInstallation: InstallationRecordingContextStoring {
    var onboardingContext: InstallationRecordingContext
    var backupImportRecovery: BackupCoordinator.DurableImportRecovery?
    var onboardingImportCompletion: BackupCoordinator.OnboardingImportCompletion?
    var failsControlWrite = false
    struct WriteFailure: Error {}

    init(deviceID: RecordingDeviceID) {
        onboardingContext = .init(
            currentDevice: .init(id: deviceID, systemName: "Test phone", kind: .phone),
            registeredAt: Date(),
            recordingChoice: .unconfirmed,
            isRejoining: false,
        )
    }

    func resolve() throws -> InstallationRecordingContext {
        onboardingContext
    }

    func confirmInitialRecording(isEnabled: Bool) throws -> InstallationRecordingContext {
        if onboardingContext.automaticRecordingEnabled == nil {
            onboardingContext = onboardingContext.confirmingInitialRecording(isEnabled: isEnabled)
        }
        return onboardingContext
    }

    func setAutomaticRecordingEnabled(_ isEnabled: Bool) throws {
        onboardingContext = onboardingContext.settingAutomaticRecordingEnabled(
            isEnabled,
            at: Date(),
        )
    }

    func setRecordingControl(_ control: RecordingInstallationControl) throws {
        if failsControlWrite { throw WriteFailure() }
        onboardingContext = onboardingContext.settingRecordingControl(control)
    }

    func rejoin() throws -> InstallationRecordingContext {
        onboardingContext = .init(
            currentDevice: .init(
                id: .init(rawValue: UUID()),
                systemName: "Test phone",
                kind: .phone,
            ),
            registeredAt: Date(),
            recordingChoice: .unconfirmed,
            isRejoining: true,
        )
        return onboardingContext
    }

    func setBackupImportRecovery(_ recovery: BackupCoordinator.DurableImportRecovery?) {
        backupImportRecovery = recovery
    }

    func recordOnboardingImportCompletion(_ completion: BackupCoordinator
        .OnboardingImportCompletion)
    {
        onboardingImportCompletion = completion
    }

    func reset() throws {
        _ = try rejoin()
    }
}
