import Foundation
import WhereCore

/// In-memory installation context persistence used by previews and unit tests.
@_spi(Testing)
@MainActor
public final class InMemoryInstallationRecordingContextStore:
    InstallationRecordingContextStoring
{
    public private(set) var onboardingContext: InstallationRecordingContext
    public private(set) var backupImportRecovery: BackupCoordinator.DurableImportRecovery?
    public private(set) var onboardingImportCompletion:
        BackupCoordinator.OnboardingImportCompletion?
    private let makeUUID: @MainActor () -> UUID
    private let now: @MainActor () -> Date

    public convenience init(context: InstallationRecordingContext) {
        self.init(
            context: context,
            makeUUID: { UUID() },
            now: { Date() },
        )
    }

    public init(
        context: InstallationRecordingContext,
        makeUUID: @escaping @MainActor () -> UUID,
        now: @escaping @MainActor () -> Date,
    ) {
        onboardingContext = context
        backupImportRecovery = nil
        onboardingImportCompletion = nil
        self.makeUUID = makeUUID
        self.now = now
    }

    public func resolve() throws -> InstallationRecordingContext {
        onboardingContext
    }

    public func confirmInitialRecording(
        isEnabled: Bool,
    ) throws -> InstallationRecordingContext {
        if onboardingContext.initialRecordingChoice != nil { return onboardingContext }
        onboardingContext = onboardingContext.confirmingInitialRecording(
            isEnabled: isEnabled,
            policyChangeID: makeUUID(),
            confirmedAt: now(),
        )
        return onboardingContext
    }

    public func setBackupImportRecovery(
        _ recovery: BackupCoordinator.DurableImportRecovery?,
    ) {
        backupImportRecovery = recovery
    }

    public func recordOnboardingImportCompletion(
        _ completion: BackupCoordinator.OnboardingImportCompletion,
    ) {
        onboardingImportCompletion = completion
    }

    public func reset() throws {
        backupImportRecovery = nil
        onboardingImportCompletion = nil
        onboardingContext = InstallationRecordingContext(
            currentDevice: CurrentRecordingDevice(
                id: RecordingDeviceID(rawValue: makeUUID()),
                systemName: onboardingContext.currentDevice.systemName,
                kind: onboardingContext.currentDevice.kind,
            ),
            registeredAt: now(),
            initialRecordingChoice: nil,
        )
    }
}
