/// Persistence boundary for the device-local installation context.
///
/// The app supplies a file-backed implementation at its composition root.
/// Tests and previews inject an in-memory implementation, so domain consumers
/// and views never reach for `FileManager`, `UIDevice`, or `UserDefaults`.
@MainActor
public protocol InstallationRecordingContextStoring: AnyObject {
    /// Context used to render onboarding before any real store is opened.
    var onboardingContext: InstallationRecordingContext { get }

    /// Resolve this installation's context. Repeated calls return the same
    /// value for the lifetime of the store object.
    func resolve() throws -> InstallationRecordingContext

    /// Persist the first explicit choice and its immutable event time beside
    /// the installation identity and immutable profile time. Later calls return
    /// that frozen choice; subsequent intent changes belong in the synced assignment stream.
    func confirmInitialRecording(isEnabled: Bool) throws -> InstallationRecordingContext

    /// Durable two-phase state for an import started by this installation. Kept beside the
    /// identity so a recreated service layer cannot forget a committed cleanup or onboarding
    /// acknowledgement boundary.
    var backupImportRecovery: BackupCoordinator.DurableImportRecovery? { get }

    /// Atomically replace the import-recovery marker without changing the installation identity.
    func setBackupImportRecovery(
        _ recovery: BackupCoordinator.DurableImportRecovery?,
    ) throws

    /// Terminal proof that this installation completed onboarding through an imported archive.
    /// Kept independently from active recovery so later Settings imports cannot erase it.
    var onboardingImportCompletion: BackupCoordinator.OnboardingImportCompletion? { get }

    /// Persist the completion proof before an acknowledged onboarding recovery marker is cleared.
    func recordOnboardingImportCompletion(
        _ completion: BackupCoordinator.OnboardingImportCompletion,
    ) throws

    /// Forget the logical installation as part of erase-and-reset.
    func reset() throws
}

extension InstallationRecordingContextStoring {
    /// Bridge this main-actor sidecar to the coordinator's async persistence seam without
    /// exposing the adapter's filesystem details to Core.
    public var backupImportRecoveryPersistence: BackupCoordinator.ImportRecoveryPersistence {
        BackupCoordinator.ImportRecoveryPersistence(
            load: { @MainActor [self] in backupImportRecovery },
            save: { @MainActor [self] recovery in
                try setBackupImportRecovery(recovery)
            },
            recordOnboardingCompletion: { @MainActor [self] completion in
                try recordOnboardingImportCompletion(completion)
            },
        )
    }
}
