import Foundation
import UIKit
import WhereCore

/// File-backed installation context owned by the app composition root.
///
/// The sidecar is excluded from backup, so restoring Where onto another device
/// cannot clone the source installation's identity or recording consent. A new
/// context stays in memory until onboarding confirms its first choice, which
/// keeps merely viewing onboarding or entering demo mode free of durable writes.
/// The sidecar also freezes the timestamp used by the immutable device profile
/// and retains active import recovery plus terminal onboarding-import authority,
/// so retries and cold-launch repair are deterministic.
@MainActor
public final class FileInstallationRecordingContextStore:
    InstallationRecordingContextStoring
{
    private static let logger = WhereLog.root(OnboardingViewLog.self)

    private enum Resolution {
        case resolved(InstallationRecordingContext)
        case failed(any Error, proposed: InstallationRecordingContext)
        /// The authoritative directory was atomically retired, but deleting that retired copy
        /// failed. The new context is the logical result and must not rotate again on retry.
        case resetCleanupRequired(
            WhereServices.ResetCleanupError,
            proposed: InstallationRecordingContext,
        )

        var onboardingContext: InstallationRecordingContext {
            switch self {
                case let .resolved(context): context
                case let .failed(_, proposed), let .resetCleanupRequired(_, proposed): proposed
            }
        }

        func get() throws -> InstallationRecordingContext {
            switch self {
                case let .resolved(context): context
                case let .failed(error, _): throw error
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
            let strategy: Strategy
            let summary: Summary
            let phase: Phase
            let cleanupCompleted: Bool
            let onboardingAcknowledged: Bool

            init(_ recovery: BackupCoordinator.DurableImportRecovery) {
                let details = recovery.details
                transactionID = details.transactionID
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

            var value: BackupCoordinator.DurableImportRecovery {
                let strategy: BackupCoordinator.ImportStrategy = switch strategy {
                    case .merge: .merge
                    case .replace: .replace
                }
                let details = BackupCoordinator.ImportRecoveryDetails(
                    transactionID: transactionID,
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

        let deviceID: UUID
        let systemName: String
        let kind: RecordingDeviceKind
        let registeredAt: Date
        let automaticRecordingEnabled: Bool?
        let recordingEnabledAt: Date?
        let isRejoining: Bool?
        let backupImportRecovery: BackupImportRecovery?
        let onboardingImportCompletionID: UUID?

        enum CodingKeys: String, CodingKey {
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
            let recordingChoice: InstallationRecordingContext.RecordingChoice =
                switch automaticRecordingEnabled {
                    case nil: .unconfirmed
                    case false?: .off
                    case true?: .on(
                            enabledAt: recordingEnabledAt ?? registeredAt,
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
                isRejoining: isRejoining ?? false,
            )
        }
    }

    private struct LoadedContext {
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
        fileURL: URL,
        fileManager: FileManager,
        systemName: String,
        kind: RecordingDeviceKind,
        makeUUID: @escaping @MainActor () -> UUID,
        now: @escaping @MainActor () -> Date,
    ) {
        self.init(
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
        fileURL: URL,
        fileManager: FileManager,
        systemName: String,
        kind: RecordingDeviceKind,
        makeUUID: @escaping @MainActor () -> UUID,
        now: @escaping @MainActor () -> Date,
        initialFailure: (any Error)?,
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.systemName = systemName
        self.kind = kind
        self.makeUUID = makeUUID
        self.now = now
        backupImportRecovery = nil
        onboardingImportCompletion = nil

        let proposed = Self.proposedContext(
            systemName: systemName,
            kind: kind,
            id: makeUUID(),
            registeredAt: now(),
            isRejoining: false,
        )
        if let initialFailure {
            resolution = .failed(initialFailure, proposed: proposed)
        } else {
            do {
                try Self.finishInterruptedReset(
                    for: fileURL,
                    fileManager: fileManager,
                )
                let loaded = try Self.load(from: fileURL, fileManager: fileManager)
                resolution = .resolved(loaded?.context ?? proposed)
                backupImportRecovery = loaded?.backupImportRecovery
                onboardingImportCompletion = loaded?.onboardingImportCompletion
            } catch {
                let resetPendingURL = Self.resetPendingURL(for: fileURL)
                if fileManager.fileExists(
                    atPath: resetPendingURL.path(percentEncoded: false),
                ) {
                    resolution = .resetCleanupRequired(
                        WhereServices.ResetCleanupError(underlying: error),
                        proposed: proposed,
                    )
                } else {
                    resolution = .failed(error, proposed: proposed)
                }
            }
        }
    }

    public var onboardingContext: InstallationRecordingContext {
        resolution.onboardingContext
    }

    public func resolve() throws -> InstallationRecordingContext {
        try resolution.get()
    }

    public func confirmInitialRecording(
        isEnabled: Bool,
    ) throws -> InstallationRecordingContext {
        let context = try resolution.get()
        if context.automaticRecordingEnabled != nil { return context }

        let confirmed = context.confirmingInitialRecording(isEnabled: isEnabled)
        try persist(
            confirmed,
            backupImportRecovery: backupImportRecovery,
            onboardingImportCompletion: onboardingImportCompletion,
        )
        resolution = .resolved(confirmed)
        return confirmed
    }

    public func setAutomaticRecordingEnabled(_ isEnabled: Bool) throws {
        let updated = try resolution.get().settingAutomaticRecordingEnabled(isEnabled, at: now())
        try persist(
            updated,
            backupImportRecovery: backupImportRecovery,
            onboardingImportCompletion: onboardingImportCompletion,
        )
        resolution = .resolved(updated)
    }

    public func rejoin() throws -> InstallationRecordingContext {
        let proposed = Self.proposedContext(
            systemName: systemName,
            kind: kind,
            id: makeUUID(),
            registeredAt: now(),
            isRejoining: true,
        )
        try persist(
            proposed,
            backupImportRecovery: backupImportRecovery,
            onboardingImportCompletion: onboardingImportCompletion,
        )
        resolution = .resolved(proposed)
        return proposed
    }

    public func setBackupImportRecovery(
        _ recovery: BackupCoordinator.DurableImportRecovery?,
    ) throws {
        let context = try resolution.get()
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
        let context = try resolution.get()
        try persist(
            context,
            backupImportRecovery: backupImportRecovery,
            onboardingImportCompletion: completion,
        )
        onboardingImportCompletion = completion
    }

    public func reset() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        let resetPendingURL = Self.resetPendingURL(for: fileURL)
        let proposed: InstallationRecordingContext
        let wasAlreadyCommitted: Bool
        switch resolution {
            case let .resetCleanupRequired(_, pending):
                proposed = pending
                wasAlreadyCommitted = true
            case .resolved, .failed:
                proposed = Self.proposedContext(
                    systemName: systemName,
                    kind: kind,
                    id: makeUUID(),
                    registeredAt: now(),
                    isRejoining: false,
                )
                wasAlreadyCommitted = false
        }

        if fileManager.fileExists(atPath: resetPendingURL.path(percentEncoded: false)) {
            do {
                try fileManager.removeItem(at: resetPendingURL)
            } catch {
                let cleanupError = WhereServices.ResetCleanupError(underlying: error)
                resolution = .resetCleanupRequired(cleanupError, proposed: proposed)
                throw cleanupError
            }
            if wasAlreadyCommitted {
                backupImportRecovery = nil
                onboardingImportCompletion = nil
                resolution = .resolved(proposed)
                return
            }
        }

        guard fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) else {
            backupImportRecovery = nil
            onboardingImportCompletion = nil
            resolution = .resolved(proposed)
            return
        }

        // Renaming inside Application Support is the commit point: either the old authoritative
        // directory still exists, or it has the reset-pending name and can never be loaded as a
        // live installation again. Deleting the retired copy is retryable cleanup after that.
        try fileManager.moveItem(at: directoryURL, to: resetPendingURL)
        backupImportRecovery = nil
        onboardingImportCompletion = nil
        do {
            try fileManager.removeItem(at: resetPendingURL)
        } catch {
            let cleanupError = WhereServices.ResetCleanupError(underlying: error)
            resolution = .resetCleanupRequired(cleanupError, proposed: proposed)
            throw cleanupError
        }
        resolution = .resolved(proposed)
    }

    /// Hardware-family mapping kept at the UIKit composition boundary.
    @_spi(Testing)
    public static func kind(for idiom: UIUserInterfaceIdiom) -> RecordingDeviceKind {
        switch idiom {
            case .phone: .phone
            case .pad: .tablet
            case .unspecified, .tv, .carPlay, .mac, .vision: .other
            @unknown default: .other
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
                Self.logger { .discardedCorruptInstallationContextPending }
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
            context: stored.value,
            backupImportRecovery: stored.backupImportRecovery?.value,
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
            logger {
                .installationContextSecurityCleanupFailed(
                    exclusionDescription: exclusionError.localizedDescription,
                    cleanupDescription: error.localizedDescription,
                )
            }
            throw SecurityCleanupError()
        }
        throw exclusionError
    }
}
