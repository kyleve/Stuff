import Foundation
import UIKit
import WhereCore

/// Installation context composed from device-only Keychain identity and a local sidecar.
///
/// The backup-excluded sidecar owns consent and import recovery. Keychain retains the identity
/// and profile creation time across same-device reinstalls when its item survives. Confirmed
/// absence alone permits a new identity; inaccessible storage fails before setup or store open.
/// New installs write nothing until confirmation. Ordinary updates adopt the existing excluded
/// sidecar identity once. Reset/rejoin commit their rotation in Keychain before file cleanup.
@MainActor
public final class FileInstallationRecordingContextStore:
    InstallationRecordingContextStoring
{
    private static let logger = WhereLog.root(OnboardingViewLog.self)

    private enum Resolution {
        case unresolved
        case resolved(InstallationRecordingContext)
        case failed(any Error)
        /// The Keychain rotation committed. Sidecar retirement or deletion still needs cleanup;
        /// retries must retain the committed replacement identity.
        case resetCleanupRequired(
            WhereServices.ResetCleanupError,
            proposed: InstallationRecordingContext,
        )

        func get() throws -> InstallationRecordingContext {
            switch self {
                case .unresolved: preconditionFailure(
                        "Installation context initialization is incomplete.",
                    )
                case let .resolved(context): context
                case let .failed(error): throw error
                case let .resetCleanupRequired(error, _): throw error
            }
        }
    }

    private struct StoredContext: Codable {
        struct BackupImportRecovery: Codable {
            enum Strategy: String, Codable {
                case merge = "backup-merge"
                case replace = "backup-replace"
            }

            struct Summary: Codable {
                let sampleCount: Int
                let evidenceCount: Int
                let manualDayCount: Int
                let dismissedIssueCount: Int
                let trackedRegionCount: Int
                let recordingDeviceCount: Int
                let recordingDeviceRemovalCount: Int

                init(_ summary: BackupCoordinator.ImportSummary) {
                    sampleCount = summary.sampleCount
                    evidenceCount = summary.evidenceCount
                    manualDayCount = summary.manualDayCount
                    dismissedIssueCount = summary.dismissedIssueCount
                    trackedRegionCount = summary.trackedRegionCount
                    recordingDeviceCount = summary.recordingDeviceCount
                    recordingDeviceRemovalCount = summary.recordingDeviceRemovalCount
                }

                var value: BackupCoordinator.ImportSummary {
                    BackupCoordinator.ImportSummary(
                        sampleCount: sampleCount,
                        evidenceCount: evidenceCount,
                        manualDayCount: manualDayCount,
                        dismissedIssueCount: dismissedIssueCount,
                        trackedRegionCount: trackedRegionCount,
                        recordingDeviceCount: recordingDeviceCount,
                        recordingDeviceRemovalCount: recordingDeviceRemovalCount,
                    )
                }
            }

            enum Phase: String, Codable {
                case prepared = "backup-prepared"
                case committed = "backup-committed"
            }

            let transactionID: UUID
            let installationID: RecordingDeviceID?
            let strategy: Strategy
            let summary: Summary
            let phase: Phase
            let cleanupCompleted: Bool
            let onboardingAcknowledged: Bool

            init(_ recovery: BackupCoordinator.DurableImportRecovery) {
                let details = recovery.details
                transactionID = details.transactionID
                installationID = details.installationID
                strategy = switch details.strategy {
                    case .merge: .merge
                    case .replace: .replace
                }
                summary = Summary(details.summary)
                switch recovery {
                    case .prepared:
                        phase = .prepared
                        cleanupCompleted = false
                        onboardingAcknowledged = false
                    case let .committed(_, completed, acknowledged):
                        phase = .committed
                        cleanupCompleted = completed
                        onboardingAcknowledged = acknowledged
                }
            }

            func value(sidecarDeviceID: RecordingDeviceID) -> BackupCoordinator
                .DurableImportRecovery
            {
                let strategy: BackupCoordinator.ImportStrategy = switch strategy {
                    case .merge: .merge
                    case .replace: .replace
                }
                let details = BackupCoordinator.ImportRecoveryDetails(
                    transactionID: transactionID,
                    installationID: installationID ?? sidecarDeviceID,
                    strategy: strategy,
                    summary: summary.value,
                )
                return switch phase {
                    case .prepared: .prepared(details)
                    case .committed: .committed(
                            details,
                            cleanupCompleted: cleanupCompleted,
                            onboardingAcknowledged: onboardingAcknowledged,
                        )
                }
            }
        }

        let usesKeychainIdentity: Bool?
        let hasCompletedSetup: Bool?
        let deviceID: UUID
        let systemName: String
        let kind: RecordingDeviceKind
        let registeredAt: Date
        let automaticRecordingEnabled: Bool?
        let recordingEnabledAt: Date?
        let isRejoining: Bool
        let backupImportRecovery: BackupImportRecovery?
        let onboardingImportCompletionID: UUID?

        enum CodingKeys: String, CodingKey {
            case usesKeychainIdentity
            case hasCompletedSetup
            case deviceID
            case systemName
            case kind
            case registeredAt
            case automaticRecordingEnabled
            case recordingEnabledAt
            case isRejoining
            case backupImportRecovery
            case onboardingImportCompletionID
        }

        init(
            _ context: InstallationRecordingContext,
            backupImportRecovery: BackupCoordinator.DurableImportRecovery?,
            onboardingImportCompletion: BackupCoordinator.OnboardingImportCompletion?,
        ) {
            usesKeychainIdentity = true
            hasCompletedSetup = context.hasCompletedSetup
            deviceID = context.currentDevice.id.rawValue
            systemName = context.currentDevice.systemName
            kind = context.currentDevice.kind
            registeredAt = context.registeredAt
            automaticRecordingEnabled = context.automaticRecordingEnabled
            recordingEnabledAt = context.recordingEnabledAt
            isRejoining = context.isRejoining
            self.backupImportRecovery = backupImportRecovery.map(BackupImportRecovery.init)
            onboardingImportCompletionID = onboardingImportCompletion?.transactionID
        }

        var value: InstallationRecordingContext {
            let setup: InstallationRecordingContext
                .SetupCompletion = hasCompletedSetup == false ? .pending : .complete
            let recordingChoice: InstallationRecordingContext.RecordingChoice =
                switch automaticRecordingEnabled {
                    case nil: .unconfirmed
                    case false?: .off(setup: setup)
                    case true?: .on(
                            enabledAt: recordingEnabledAt ?? registeredAt,
                            setup: setup,
                        )
                }
            return InstallationRecordingContext(
                currentDevice: CurrentRecordingDevice(
                    id: RecordingDeviceID(rawValue: deviceID),
                    systemName: systemName,
                    kind: kind,
                ),
                registeredAt: registeredAt,
                recordingChoice: recordingChoice,
                isRejoining: isRejoining,
            )
        }
    }

    private struct LoadedContext {
        let usesKeychainIdentity: Bool
        let context: InstallationRecordingContext
        let backupImportRecovery: BackupCoordinator.DurableImportRecovery?
        let onboardingImportCompletion: BackupCoordinator.OnboardingImportCompletion?
    }

    private struct SecurityCleanupError: LocalizedError {
        var errorDescription: String? {
            String(localized: .onboardingInstallationSecurityError)
        }
    }

    private static let directoryName = "RecordingInstallationContext"
    private static let fileName = "context.json"

    private let identityStore: any RecordingIdentityStoring
    private let configurationFailure: (any Error)?
    private var loadedIdentity: InstallationRecordingIdentity?
    private let fileURL: URL
    private let fileManager: FileManager
    private let systemName: String
    private let kind: RecordingDeviceKind
    private let makeUUID: @MainActor () -> UUID
    private let now: @MainActor () -> Date
    private var resolution: Resolution
    public private(set) var backupImportRecovery: BackupCoordinator.DurableImportRecovery?
    public private(set) var onboardingImportCompletion:
        BackupCoordinator.OnboardingImportCompletion?

    /// The production sidecar in Application Support, composed from the current
    /// hardware without persisting the user-assigned device name.
    public convenience init() {
        let device = UIDevice.current
        guard let bundleID = Bundle.main.bundleIdentifier else {
            preconditionFailure("The app must provide its bundle identity for Keychain storage.")
        }
        let identityStore =
            KeychainRecordingIdentityStore(service: bundleID + ".recording-identity")
        let directory: URL
        do {
            directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false,
            )
        } catch {
            // Preserve the exact resolution failure so onboarding can render
            // and the launch can surface it when the user tries to continue.
            self.init(
                identityStore: identityStore,
                fileURL: URL(filePath: "/invalid/recording-installation-context.json"),
                fileManager: .default,
                systemName: device.model,
                kind: Self.kind(for: device.userInterfaceIdiom),
                makeUUID: { UUID() },
                now: { Date() },
                initialFailure: error,
            )
            return
        }
        self.init(
            identityStore: identityStore,
            fileURL: directory
                .appending(path: Self.directoryName, directoryHint: .isDirectory)
                .appending(path: Self.fileName),
            fileManager: .default,
            systemName: device.model,
            kind: Self.kind(for: device.userInterfaceIdiom),
            makeUUID: { UUID() },
            now: { Date() },
        )
    }

    /// Explicit-dependency initializer for tests and alternate composition.
    @_spi(Testing)
    public convenience init(
        identityStore: any RecordingIdentityStoring,
        fileURL: URL,
        fileManager: FileManager,
        systemName: String,
        kind: RecordingDeviceKind,
        makeUUID: @escaping @MainActor () -> UUID,
        now: @escaping @MainActor () -> Date,
    ) {
        self.init(
            identityStore: identityStore,
            fileURL: fileURL,
            fileManager: fileManager,
            systemName: systemName,
            kind: kind,
            makeUUID: makeUUID,
            now: now,
            initialFailure: nil,
        )
    }

    private init(
        identityStore: any RecordingIdentityStoring,
        fileURL: URL,
        fileManager: FileManager,
        systemName: String,
        kind: RecordingDeviceKind,
        makeUUID: @escaping @MainActor () -> UUID,
        now: @escaping @MainActor () -> Date,
        initialFailure: (any Error)?,
    ) {
        self.identityStore = identityStore
        configurationFailure = initialFailure
        loadedIdentity = nil
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.systemName = systemName
        self.kind = kind
        self.makeUUID = makeUUID
        self.now = now
        backupImportRecovery = nil
        onboardingImportCompletion = nil

        resolution = .unresolved
        do { try reload() }
        catch { recordFailure(error) }
    }

    public var onboardingContext: InstallationRecordingContext {
        get throws { try resolve() }
    }

    public func resolve() throws -> InstallationRecordingContext {
        if case .failed = resolution {
            do { try reload() }
            catch { recordFailure(error) }
        }
        return try resolution.get()
    }

    public func confirmInitialRecording(
        isEnabled: Bool,
    ) throws -> InstallationRecordingContext {
        let context = try resolve()
        if context.automaticRecordingEnabled != nil { return context }

        let confirmed = context.confirmingInitialRecording(isEnabled: isEnabled, at: now())
        try persist(
            confirmed,
            backupImportRecovery: backupImportRecovery,
            onboardingImportCompletion: onboardingImportCompletion,
        )
        resolution = .resolved(confirmed)
        return confirmed
    }

    public func setAutomaticRecordingEnabled(_ isEnabled: Bool) throws {
        let updated = try resolve().settingAutomaticRecordingEnabled(isEnabled, at: now())
        try persist(
            updated,
            backupImportRecovery: backupImportRecovery,
            onboardingImportCompletion: onboardingImportCompletion,
        )
        resolution = .resolved(updated)
    }

    public func completeSetup() throws {
        let completed = try resolve().completingSetup()
        try persist(
            completed,
            backupImportRecovery: backupImportRecovery,
            onboardingImportCompletion: onboardingImportCompletion,
        )
        resolution = .resolved(completed)
    }

    public func rejoin() throws -> InstallationRecordingContext {
        let current = try resolve()
        if current.isRejoining, current.automaticRecordingEnabled == nil { return current }
        let identity = try rotateIdentity(creation: .rejoin)
        let proposed = context(for: identity, isRejoining: true)
        do {
            try persist(
                proposed,
                backupImportRecovery: backupImportRecovery,
                onboardingImportCompletion: onboardingImportCompletion,
            )
            resolution = .resolved(proposed)
            return proposed
        } catch {
            recordFailure(error)
            throw error
        }
    }

    public func setBackupImportRecovery(
        _ recovery: BackupCoordinator.DurableImportRecovery?,
    ) throws {
        let context = try resolve()
        try persist(
            context,
            backupImportRecovery: recovery,
            onboardingImportCompletion: onboardingImportCompletion,
        )
        backupImportRecovery = recovery
    }

    public func recordOnboardingImportCompletion(
        _ completion: BackupCoordinator.OnboardingImportCompletion,
    ) throws {
        let context = try resolve()
        try persist(
            context,
            backupImportRecovery: backupImportRecovery,
            onboardingImportCompletion: completion,
        )
        onboardingImportCompletion = completion
    }

    public func reset() throws {
        let proposed: InstallationRecordingContext
        switch resolution {
            case let .resetCleanupRequired(_, pending): proposed = pending
            case .unresolved: preconditionFailure(
                    "Installation context initialization is incomplete.",
                )
            case .resolved, .failed:
                _ = try resolve()
                proposed = try context(for: rotateIdentity(creation: .reset), isRejoining: false)
        }
        try clearSidecar(replacement: proposed)
    }

    private func clearSidecar(replacement: InstallationRecordingContext) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        let pendingURL = Self.resetPendingURL(for: fileURL)
        backupImportRecovery = nil
        onboardingImportCompletion = nil
        do {
            if fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: pendingURL)
            }
            if fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) {
                try fileManager.moveItem(at: directoryURL, to: pendingURL)
                try fileManager.removeItem(at: pendingURL)
            }
            resolution = .resolved(replacement)
        } catch {
            let error = WhereServices.ResetCleanupError(underlying: error)
            resolution = .resetCleanupRequired(error, proposed: replacement)
            throw error
        }
    }

    private func context(for identity: InstallationRecordingIdentity, isRejoining: Bool)
        -> InstallationRecordingContext
    {
        Self.proposedContext(
            systemName: systemName,
            kind: kind,
            id: identity.deviceID.rawValue,
            registeredAt: identity.registeredAt,
            isRejoining: isRejoining,
        )
    }

    private func reload() throws {
        if let configurationFailure { throw configurationFailure }
        // Identity failure precedes file recovery and UUID allocation. Absence alone authorizes
        // proposing a new identity; a locked or corrupt Keychain never takes that path.
        loadedIdentity = try identityStore.load()
        do { try Self.finishInterruptedReset(for: fileURL, fileManager: fileManager) }
        catch { throw WhereServices.ResetCleanupError(underlying: error) }
        let loaded = try Self.load(from: fileURL, fileManager: fileManager)
        backupImportRecovery = loaded?.backupImportRecovery
        onboardingImportCompletion = loaded?.onboardingImportCompletion
        let sidecar: RecordingIdentityRecoveryPolicy.Sidecar = if let loaded {
            loaded.usesKeychainIdentity ? .keychainBound(loaded.context) : .legacy(loaded.context)
        } else {
            .absent
        }
        switch try RecordingIdentityRecoveryPolicy.resolve(
            identity: loadedIdentity,
            sidecar: sidecar,
        ) {
            case .newIdentity:
                resolution = .resolved(Self.proposedContext(
                    systemName: systemName,
                    kind: kind,
                    id: makeUUID(),
                    registeredAt: now(),
                    isRejoining: false,
                ))
            case let .adoptLegacy(context):
                try persist(
                    context,
                    backupImportRecovery: backupImportRecovery,
                    onboardingImportCompletion: onboardingImportCompletion,
                )
                resolution = .resolved(context)
            case let .reuse(identity, confirmedContext):
                let context = confirmedContext ?? context(
                    for: identity,
                    isRejoining: loaded != nil &&
                        identity.creation == .rejoin,
                )
                if let loaded, !loaded.usesKeychainIdentity || loaded.context != context {
                    try persist(
                        context,
                        backupImportRecovery: backupImportRecovery,
                        onboardingImportCompletion: onboardingImportCompletion,
                    )
                }
                resolution = .resolved(context)
            case let .finishReset(identity):
                try clearSidecar(replacement: context(for: identity, isRejoining: false))
        }
    }

    private func recordFailure(_ error: any Error) {
        if case .resetCleanupRequired = resolution { return }
        resolution = .failed(error)
    }

    private enum IdentityError: Error { case changed }

    private func ensureIdentity(for context: InstallationRecordingContext) throws {
        if let loadedIdentity {
            guard loadedIdentity.deviceID == context.currentDevice.id,
                  try identityStore.load() == loadedIdentity
            else { throw IdentityError.changed }
        } else {
            let identity = InstallationRecordingIdentity(
                deviceID: context.currentDevice.id,
                registeredAt: context.registeredAt,
                creation: context
                    .isRejoining ? .rejoin : .initial,
            )
            try identityStore.create(identity)
            loadedIdentity = identity
        }
    }

    private func rotateIdentity(creation: InstallationRecordingIdentity.Creation) throws
        -> InstallationRecordingIdentity
    {
        if let loadedIdentity,
           try identityStore.load() != loadedIdentity { throw IdentityError.changed }
        let identity = InstallationRecordingIdentity(
            deviceID: RecordingDeviceID(rawValue: makeUUID()),
            registeredAt: now(),
            creation: creation,
        )
        if let loadedIdentity {
            try identityStore.replace(identity, expectedDeviceID: loadedIdentity.deviceID)
        } else {
            try identityStore.create(identity)
        }
        loadedIdentity = identity
        return identity
    }

    /// Hardware-family mapping kept at the UIKit composition boundary.
    @_spi(Testing)
    public static func kind(for idiom: UIUserInterfaceIdiom) -> RecordingDeviceKind {
        switch idiom {
            case .phone: .phone
            case .pad: .tablet
            case .mac: .computer
            case .tv: .other("tv")
            case .carPlay: .other("carPlay")
            case .vision: .other("vision")
            case .unspecified: .other(nil)
            @unknown default: .other("idiom-\(idiom.rawValue)")
        }
    }

    private static func proposedContext(
        systemName: String,
        kind: RecordingDeviceKind,
        id: UUID,
        registeredAt: Date,
        isRejoining: Bool,
    ) -> InstallationRecordingContext {
        InstallationRecordingContext(
            currentDevice: CurrentRecordingDevice(
                id: RecordingDeviceID(rawValue: id),
                systemName: systemName,
                kind: kind,
            ),
            registeredAt: registeredAt,
            recordingChoice: .unconfirmed,
            isRejoining: isRejoining,
        )
    }

    private static func resetPendingURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appendingPathExtension("reset-pending")
    }

    /// Finish deletion after a process stopped between the reset's atomic directory rename and
    /// cleanup. A failure keeps the tombstone in place so the next construction retries it and
    /// the old context is never loaded as authoritative again.
    private static func finishInterruptedReset(
        for fileURL: URL,
        fileManager: FileManager,
    ) throws {
        let pendingURL = resetPendingURL(for: fileURL)
        guard fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: pendingURL)
    }

    private static func load(
        from fileURL: URL,
        fileManager: FileManager,
    ) throws -> LoadedContext? {
        let directoryURL = fileURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) else {
            return nil
        }
        // A prior process may have died at any point. Secure the directory before inspecting or
        // deleting contents so even a pending file whose own attribute was never set is safe.
        do {
            try excludeFromBackup(directoryURL)
        } catch {
            try discardAfterExclusionFailure(
                directoryURL: directoryURL,
                fileManager: fileManager,
                exclusionError: error,
            )
        }
        let pendingURL = fileURL.appendingPathExtension("pending")
        if fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false)) {
            do {
                try excludeFromBackup(pendingURL)
            } catch {
                try discardAfterExclusionFailure(
                    directoryURL: directoryURL,
                    fileManager: fileManager,
                    exclusionError: error,
                )
            }
            let pendingContext: LoadedContext
            do {
                pendingContext = try decodeContext(from: pendingURL)
            } catch is DecodingError {
                // An atomic write either produced a complete current value or unusable bytes.
                // Keep an older authoritative context when one exists, but never retry a
                // permanently malformed pending replacement on every launch.
                Self.logger.discardedCorruptInstallationContextPending()
                try fileManager.removeItem(at: pendingURL)
                return try loadAuthoritativeContext(
                    from: fileURL,
                    directoryURL: directoryURL,
                    fileManager: fileManager,
                )
            }
            if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                _ = try fileManager.replaceItemAt(
                    fileURL,
                    withItemAt: pendingURL,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly,
                )
            } else {
                try fileManager.moveItem(at: pendingURL, to: fileURL)
            }
            do {
                try excludeFromBackup(fileURL)
            } catch {
                try discardAfterExclusionFailure(
                    directoryURL: directoryURL,
                    fileManager: fileManager,
                    exclusionError: error,
                )
            }
            return pendingContext
        }
        return try loadAuthoritativeContext(
            from: fileURL,
            directoryURL: directoryURL,
            fileManager: fileManager,
        )
    }

    private static func loadAuthoritativeContext(
        from fileURL: URL,
        directoryURL: URL,
        fileManager: FileManager,
    ) throws -> LoadedContext? {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }
        // Reassert this on every launch as defense against a restored/copied file whose
        // extended attributes did not survive. Never accept an identity that can be backed up.
        do {
            try excludeFromBackup(fileURL)
        } catch {
            try discardAfterExclusionFailure(
                directoryURL: directoryURL,
                fileManager: fileManager,
                exclusionError: error,
            )
        }
        return try decodeContext(from: fileURL)
    }

    private static func decodeContext(from fileURL: URL) throws -> LoadedContext {
        let stored = try JSONDecoder().decode(
            StoredContext.self,
            from: Data(contentsOf: fileURL),
        )
        return LoadedContext(
            usesKeychainIdentity: stored.usesKeychainIdentity == true,
            context: stored.value,
            backupImportRecovery: stored.backupImportRecovery?.value(
                sidecarDeviceID: RecordingDeviceID(rawValue: stored.deviceID),
            ),
            onboardingImportCompletion: stored.onboardingImportCompletionID.map {
                BackupCoordinator.OnboardingImportCompletion(transactionID: $0)
            },
        )
    }

    private func persist(
        _ context: InstallationRecordingContext,
        backupImportRecovery: BackupCoordinator.DurableImportRecovery?,
        onboardingImportCompletion: BackupCoordinator.OnboardingImportCompletion?,
    ) throws {
        try ensureIdentity(for: context)
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
        )
        // Secure the empty directory before any identity bytes are written. Atomic-write scratch
        // files and our pending replacement therefore inherit a backup-excluded ancestor even if
        // the process dies before their individual resource values are applied.
        try Self.excludeFromBackup(directoryURL)
        let pendingURL = fileURL.appendingPathExtension("pending")
        if fileManager.fileExists(atPath: pendingURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: pendingURL)
        }
        // Mark the replacement inode before it acquires the authoritative path as a second layer
        // of defense beyond the already-excluded directory.
        try JSONEncoder().encode(StoredContext(
            context,
            backupImportRecovery: backupImportRecovery,
            onboardingImportCompletion: onboardingImportCompletion,
        )).write(
            to: pendingURL,
            options: [.atomic, .noFileProtection],
        )
        try Self.excludeFromBackup(pendingURL)
        if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(
                fileURL,
                withItemAt: pendingURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly,
            )
        } else {
            try fileManager.moveItem(at: pendingURL, to: fileURL)
        }
        // Verify/reapply after the rename too. The pending inode was already excluded, so a
        // failure here does not expose its contents; a later launch retries before decoding.
        try Self.excludeFromBackup(fileURL)
    }

    private static func excludeFromBackup(_ fileURL: URL) throws {
        var persistedURL = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try persistedURL.setResourceValues(resourceValues)
    }

    /// An identity whose backup exclusion cannot be proven is unusable and unsafe to retain.
    /// Remove the dedicated directory, then surface the original exclusion failure. If removal
    /// also fails, surface both failures so the privacy problem is never hidden.
    private static func discardAfterExclusionFailure(
        directoryURL: URL,
        fileManager: FileManager,
        exclusionError: any Error,
    ) throws -> Never {
        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            logger.installationContextSecurityCleanupFailed(
                exclusionError: .restricted(
                    .errorDetails,
                    exclusionError,
                ),
                cleanupError: .restricted(.errorDetails, error),
            )
            throw SecurityCleanupError()
        }
        throw exclusionError
    }
}
