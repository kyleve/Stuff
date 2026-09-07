import Foundation

public struct AutomaticBackupConfiguration: Sendable {
    public let isEnabled: Bool
    public let isRecordingEnabled: Bool
    public let interval: AutomaticBackupInterval
    public let lastSuccessfulBackupAt: Date?

    public init(
        isEnabled: Bool,
        isRecordingEnabled: Bool,
        interval: AutomaticBackupInterval,
        lastSuccessfulBackupAt: Date?,
    ) {
        self.isEnabled = isEnabled
        self.isRecordingEnabled = isRecordingEnabled
        self.interval = interval
        self.lastSuccessfulBackupAt = lastSuccessfulBackupAt
    }
}

public enum AutomaticBackupRunResult: Sendable, Equatable {
    case disabled
    case notDue(nextEligibleAt: Date)
    case alreadyRunning
    case deferredUntilFirstUnlock
    case completed(exportedAt: Date)
}

/// Single-flight coordinator for due checks, encrypted export, storage, and
/// catalog change notifications.
public actor AutomaticBackupService {
    private let backup: BackupCoordinator
    private let recoveryKeys: BackupRecoveryKeyProvider
    private let storage: AutomaticBackupStorage
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let scheduler: any AutomaticBackupTaskScheduling
    private var isRunning = false
    private var changeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(
        backup: BackupCoordinator,
        recoveryKeys: BackupRecoveryKeyProvider,
        storage: AutomaticBackupStorage,
        scheduler: any AutomaticBackupTaskScheduling = NoopAutomaticBackupTaskScheduler(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.backup = backup
        self.recoveryKeys = recoveryKeys
        self.storage = storage
        self.scheduler = scheduler
        self.calendar = calendar
        self.now = now
    }

    public func runIfDue(
        configuration: AutomaticBackupConfiguration,
    ) async throws -> AutomaticBackupRunResult {
        await reconcileSchedule(configuration: configuration)
        guard configuration.isEnabled, configuration.isRecordingEnabled else {
            return .disabled
        }
        let currentDate = now()
        if let lastSuccessfulBackupAt = configuration.lastSuccessfulBackupAt {
            let next = configuration.interval.nextDate(
                after: lastSuccessfulBackupAt,
                calendar: calendar,
            )
            guard currentDate >= next else { return .notDue(nextEligibleAt: next) }
        }
        guard !isRunning else { return .alreadyRunning }
        isRunning = true
        defer { isRunning = false }

        let key: BackupRecoveryKey
        do {
            key = try await recoveryKeys.loadOrCreate()
        } catch BackupRecoveryKeyProvider.ProviderError.deferredUntilFirstUnlock {
            return .deferredUntilFirstUnlock
        }

        try Task.checkCancellation()
        _ = try await backup.writeAutomaticBackup(
            recoveryKey: key,
            exportedAt: currentDate,
            storage: storage,
        )
        notifyChanges()
        await scheduler.reconcile(
            isEnabled: true,
            earliestBeginDate: configuration.interval.nextDate(
                after: currentDate,
                calendar: calendar,
            ),
        )
        return .completed(exportedAt: currentDate)
    }

    public func reconcileSchedule(configuration: AutomaticBackupConfiguration) async {
        let isEnabled = configuration.isEnabled && configuration.isRecordingEnabled
        let earliest = configuration.lastSuccessfulBackupAt.map {
            configuration.interval.nextDate(after: $0, calendar: calendar)
        } ?? now()
        await scheduler.reconcile(
            isEnabled: isEnabled,
            earliestBeginDate: isEnabled ? earliest : nil,
        )
    }

    public func catalog() async throws -> AutomaticBackupCatalog {
        try await storage.catalog()
    }

    public func recoveryKey() async throws -> String {
        try await recoveryKeys.loadOrCreate().base64Encoded
    }

    /// Resolves the synchronized key or validates a user-entered recovery key.
    /// Entered keys are returned as values only and are never persisted.
    public func restoreRecoveryKey(
        explicitBase64: String?,
    ) async throws -> BackupRecoveryKey? {
        if let explicitBase64, !explicitBase64.isEmpty {
            return try BackupRecoveryKey(base64Encoded: explicitBase64)
        }
        return try await recoveryKeys.loadExisting()
    }

    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        changeContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeChangeContinuation(id) }
        }
        return stream
    }

    private func notifyChanges() {
        for continuation in changeContinuations.values {
            continuation.yield()
        }
    }

    private func removeChangeContinuation(_ id: UUID) {
        changeContinuations[id] = nil
    }
}
