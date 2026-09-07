import Foundation

public struct AutomaticBackupConfiguration: Sendable, Equatable {
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
    private struct Run {
        let id: UUID
        let task: Task<AutomaticBackupRunResult, Error>
    }

    private var run: Run?
    private var configuration: AutomaticBackupConfiguration?
    private var lastSuccessfulBackupAt: Date?
    private var scheduleTask: Task<Void, Never>?
    private var scheduleRevision = 0
    private enum Availability {
        case active
        case suspended
        case shutDown
    }

    private var availability: Availability = .active
    #if DEBUG
        @_spi(Testing) public var isRetiredForTesting: Bool {
            availability == .shutDown
        }
    #endif
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
        try Task.checkCancellation()
        guard availability == .active,
              let configuration = self.configuration else { return .disabled }
        guard configuration.isEnabled, configuration.isRecordingEnabled else {
            return .disabled
        }
        let active: Run
        if let run {
            active = run
        } else {
            let id = UUID()
            active = Run(id: id, task: Task {
                try await BackupService.withCancellation {
                    try await self.performBackup()
                }
            })
            run = active
        }
        defer { if run?.id == active.id { run = nil } }
        // Every trigger joins the same owned operation. Background expiration
        // cancels the actual export even when another trigger started it.
        return try await withTaskCancellationHandler {
            try await active.task.value
        } onCancel: { active.task.cancel() }
    }

    private func performBackup() async throws -> AutomaticBackupRunResult {
        try Task.checkCancellation()
        guard let configuration, availability == .active,
              configuration.isEnabled, configuration.isRecordingEnabled else { return .disabled }
        let currentDate = now()
        if let lastSuccessfulBackupAt = effectiveLastSuccess {
            let next = configuration.interval.nextDate(
                after: lastSuccessfulBackupAt,
                calendar: calendar,
            )
            if currentDate < next {
                await reconcileRetention()
                try Task.checkCancellation()
                return .notDue(nextEligibleAt: next)
            }
        }
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
        try Task.checkCancellation()
        lastSuccessfulBackupAt = currentDate
        notifyChanges()
        await updateSchedule()
        // A committed export remains successful if maintenance fails. Never
        // fall back or repeat an export just because pruning was unavailable.
        await reconcileRetention()
        guard availability == .active else { return .disabled }
        return .completed(exportedAt: currentDate)
    }

    public func reconcileSchedule(configuration: AutomaticBackupConfiguration) async {
        guard availability != .shutDown else { return }
        self.configuration = configuration
        if !configuration.isEnabled || !configuration.isRecordingEnabled { run?.task.cancel() }
        await updateSchedule()
    }

    private var effectiveLastSuccess: Date? {
        [lastSuccessfulBackupAt, configuration?.lastSuccessfulBackupAt].compactMap(\.self).max()
    }

    private func updateSchedule() async {
        scheduleRevision += 1
        if let scheduleTask {
            await scheduleTask.value
            return
        }
        let task = Task { await self.reconcileLatestSchedule() }
        scheduleTask = task
        await task.value
    }

    private func reconcileLatestSchedule() async {
        // Every reconciler joins this task. In particular, shutdown must not
        // return while an old submission could still cancel a new scope's job.
        defer { scheduleTask = nil }
        while true {
            let revision = scheduleRevision
            let enabled = availability == .active && configuration?.isEnabled == true
                && configuration?.isRecordingEnabled == true
            let earliest = effectiveLastSuccess.map {
                configuration?.interval.nextDate(after: $0, calendar: calendar) ?? now()
            } ?? now()
            await scheduler.reconcile(
                isEnabled: enabled,
                earliestBeginDate: enabled ? earliest : nil,
            )
            if revision == scheduleRevision { return }
        }
    }

    private func reconcileRetention() async {
        do {
            try Task.checkCancellation()
            try await storage.reconcileRetention(recoveryKeys: recoveryKeys)
            notifyChanges()
        } catch {
            WhereLog.backup(AutomaticBackupLog.self) {
                .cleanupFailed(description: error.localizedDescription)
            }
        }
    }

    /// Drain this scope before erase/logout can replace its store or preferences.
    public func shutDown() async {
        availability = .shutDown
        run?.task.cancel()
        if let run { _ = await run.task.result }
        await updateSchedule()
    }

    public func cancelCurrentRun() async {
        run?.task.cancel()
        if let run { _ = await run.task.result }
        await updateSchedule()
    }

    public func suspend() async {
        guard availability == .active else { return }
        availability = .suspended
        await cancelCurrentRun()
    }

    public func resume() async {
        guard availability == .suspended else { return }
        availability = .active
        await updateSchedule()
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
        archiveURL: URL,
        explicitBase64: String?,
    ) async throws -> BackupRecoveryKey? {
        if let explicitBase64, !explicitBase64.isEmpty {
            return try BackupRecoveryKey(base64Encoded: explicitBase64)
        }
        let task = Task.detached(priority: .utility) {
            let scoped = archiveURL.startAccessingSecurityScopedResource()
            defer { if scoped { archiveURL.stopAccessingSecurityScopedResource() } }
            return try CoordinatedBackupFileAccess.read(at: archiveURL) {
                try BackupService().readEncryptedEnvelope(at: $0).keyIdentifier
            }
        }
        let identifier = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        try Task.checkCancellation()
        return try await recoveryKeys.loadExisting(identifier: identifier)
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
