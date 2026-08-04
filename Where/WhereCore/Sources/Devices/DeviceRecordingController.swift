import Foundation

/// Owns this installation's local automatic-recording choice, synced device presence, and
/// physical GPS reconciliation.
///
/// Recording consent never enters CloudKit: the controller receives it from the backup-excluded
/// installation sidecar. Synced check-ins are advisory status, while an append-only removal
/// tombstone permanently retires an identity. Every removal read is epoch-pinned and failures
/// stop recording rather than trusting stale state.
public actor DeviceRecordingController {
    private let store: any WhereStore
    private let ingestor: LocationIngestor
    public nonisolated let currentDevice: CurrentRecordingDevice
    private let registeredAt: Date
    private let now: @Sendable () -> Date
    private let onPolicyChanged: @Sendable () async -> Void
    private let configurationBroadcaster = RecordingConfigurationBroadcaster()

    private var automaticRecordingEnabled: Bool
    private var enabledAt: Date?
    private var preparedEpochID: WhereDataEpochID?

    /// Actor reentrancy permits another command to enter at an `await`; this gate serializes the
    /// full store/physical transition rather than only its synchronous fragments.
    private var isExclusive = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var acceptsOperations = true
    private var recordingLifecycleStarted = false
    private var shouldResumeAfterPause = false
    private var isRewritePaused = false
    private var observationTask: Task<Void, Never>?
    private var needsReconciliation = false
    private var pendingOffCleanup = false
    private var nextRuntimeSequence: UInt64 = 0
    private var latestRuntimeUpdate: RecordingDeviceRuntimeUpdate?

    private static let checkInInterval: TimeInterval = 15 * 60
    private static let logger = WhereLog.root(DeviceRecordingControllerLog.self)

    private struct StoreSnapshot {
        let epoch: WhereDataEpoch
        let profiles: [RecordingDeviceProfile]
        let metadataChanges: [RecordingDeviceMetadataChange]
        let checkIns: [RecordingDeviceCheckIn]
        let removals: [RecordingDeviceRemoval]
        let currentDeviceResetBarrier: Date?
    }

    init(
        store: any WhereStore,
        ingestor: LocationIngestor,
        installationContext: InstallationRecordingContext,
        now: @escaping @Sendable () -> Date,
        onPolicyChanged: @escaping @Sendable () async -> Void,
    ) {
        guard let automaticRecordingEnabled = installationContext.automaticRecordingEnabled else {
            preconditionFailure("Recording services require a confirmed installation context.")
        }
        self.store = store
        self.ingestor = ingestor
        currentDevice = installationContext.currentDevice
        registeredAt = installationContext.registeredAt
        self.automaticRecordingEnabled = automaticRecordingEnabled
        enabledAt = installationContext.recordingEnabledAt
        self.now = now
        self.onPolicyChanged = onPolicyChanged
    }

    deinit {
        observationTask?.cancel()
        configurationBroadcaster.finishAll()
    }

    public nonisolated func runtimeUpdates() -> AsyncStream<RecordingDeviceRuntimeUpdate> {
        configurationBroadcaster.subscribe()
    }

    public func currentRuntimeUpdate() -> RecordingDeviceRuntimeUpdate? {
        latestRuntimeUpdate
    }

    /// Observe local commits and CloudKit imports for removal, status, and heartbeat changes.
    public func startMonitoringChanges() {
        recordingLifecycleStarted = true
        guard observationTask == nil else { return }
        let updates = store.changes()
        observationTask = Task { [weak self] in
            for await _ in updates {
                guard let self else { break }
                await applyObservedChange()
            }
        }
    }

    @discardableResult
    public func register(
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        recordingLifecycleStarted = true
        return try await registerAndReconcileLocked(authorization: authorization)
    }

    @discardableResult
    public func registerForOnboarding(
        desiredEnabled: Bool?,
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        recordingLifecycleStarted = true
        if let desiredEnabled, desiredEnabled != automaticRecordingEnabled {
            automaticRecordingEnabled = desiredEnabled
            enabledAt = desiredEnabled ? now() : nil
        }
        return try await registerAndReconcileLocked(authorization: authorization)
    }

    @discardableResult
    public func reconcile(
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        recordingLifecycleStarted = true
        return try await reconcileOrFailClosed(authorization: authorization)
    }

    /// Apply a choice already persisted by the installation sidecar.
    @discardableResult
    public func setAutomaticRecordingEnabled(
        _ enabled: Bool,
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        if automaticRecordingEnabled != enabled {
            automaticRecordingEnabled = enabled
            enabledAt = enabled ? now() : nil
        }
        if !enabled || pendingOffCleanup {
            try await discardRetryBacklogForOffChoice()
        }
        return try await reconcileOrFailClosed(authorization: authorization)
    }

    public func devices() async throws -> [RecordingDeviceConfiguration] {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        return try await configurationsLocked(includeRemoved: false)
    }

    /// Append a user-editable nickname change. Empty or whitespace-only input clears it.
    public func rename(
        _ deviceID: RecordingDeviceID,
        to nickname: String,
    ) async throws -> [RecordingDeviceConfiguration] {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        let snapshot = try await storeSnapshot()
        guard snapshot.profiles.contains(where: { $0.id == deviceID }) else {
            throw RecordingPersistenceError.deviceNotFound(deviceID)
        }
        let latest = Self.latestMetadata(
            for: deviceID,
            field: .nickname,
            in: snapshot.metadataChanges,
        )
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNickname = trimmed.isEmpty ? nil : trimmed
        guard latest?.nickname != resolvedNickname else {
            return try await configurationsLocked(includeRemoved: false)
        }
        let change = try RecordingDeviceMetadataChange(
            id: UUID(),
            deviceID: deviceID,
            revision: Self.nextRevision(after: latest?.revision, for: deviceID),
            changedAt: now(),
            changedByDeviceID: currentDevice.id,
            nickname: resolvedNickname,
        )
        try await store.perform(expectedDataEpochID: snapshot.epoch.id) {
            try await self.store.addRecordingDeviceMetadataChange(change)
        }
        return try await configurationsLocked(includeRemoved: false)
    }

    /// Permanently retire a remote installation identity. The target stops when it receives the
    /// tombstone; retained samples before the cutoff remain part of history.
    public func remove(
        _ deviceID: RecordingDeviceID,
    ) async throws -> [RecordingDeviceConfiguration] {
        precondition(deviceID != currentDevice.id, "The current device cannot remove itself.")
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        let snapshot = try await storeSnapshot()
        guard snapshot.profiles.contains(where: { $0.id == deviceID }) else {
            throw RecordingPersistenceError.deviceNotFound(deviceID)
        }
        guard snapshot.removals.contains(where: { $0.deviceID == deviceID }) == false else {
            return try await configurationsLocked(includeRemoved: false)
        }
        let removal = RecordingDeviceRemoval(
            id: UUID(),
            deviceID: deviceID,
            removedAt: now(),
            removedByDeviceID: currentDevice.id,
        )
        try await store.perform(expectedDataEpochID: snapshot.epoch.id) {
            try await self.store.addRecordingDeviceRemoval(removal)
        }
        await onPolicyChanged()
        return try await configurationsLocked(includeRemoved: false)
    }

    func pause() async throws {
        await beginExclusive()
        defer { endExclusive() }
        guard !isRewritePaused else {
            throw RecordingPersistenceError.recordingRewriteInProgress
        }
        isRewritePaused = true
        shouldResumeAfterPause = shouldResumeAfterPause || recordingLifecycleStarted
        recordingLifecycleStarted = false
        acceptsOperations = false
        observationTask?.cancel()
        observationTask = nil
        await ingestor.pause()
    }

    func resumeAfterFailedReset() async {
        await beginExclusive()
        defer { endExclusive() }
        await resumeLocked()
    }

    func resumeAfterImportRollback() async {
        await beginExclusive()
        defer { endExclusive() }
        await resumeLocked()
    }

    func resumeAfterImport(discardPendingSamples: Bool) async throws {
        await beginExclusive()
        acceptsOperations = true
        let shouldResume = shouldResumeAfterPause
        if discardPendingSamples {
            do {
                try await ingestor.discardRetryBacklog()
            } catch {
                isRewritePaused = false
                acceptsOperations = false
                needsReconciliation = true
                publishRuntimeState(.unavailable)
                endExclusive()
                throw error
            }
        }
        shouldResumeAfterPause = false
        isRewritePaused = false
        guard shouldResume else {
            endExclusive()
            return
        }
        startMonitoringChanges()
        do {
            let authorization = await ingestor.authorizationStatus()
            _ = try await registerAndReconcileLocked(authorization: authorization)
        } catch RecordingPersistenceError.currentDeviceRemoved {
            endExclusive()
            return
        } catch {
            needsReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            Self.logger(attachments: [.error(error, name: "import-recovery-error")]) {
                .importRecoveryFailed(description: error.localizedDescription)
            }
        }
        endExclusive()
    }

    func finishReset() async throws {
        await beginExclusive()
        do {
            try await ingestor.discardRetryBacklog()
        } catch {
            isRewritePaused = false
            needsReconciliation = true
            publishRuntimeState(.unavailable)
            endExclusive()
            throw error
        }
        shouldResumeAfterPause = false
        isRewritePaused = false
        endExclusive()
    }

    /// Permanently close the removed scope before the app rotates its local identity.
    public func retireForRejoin() async throws {
        await beginExclusive()
        acceptsOperations = false
        recordingLifecycleStarted = false
        observationTask?.cancel()
        observationTask = nil
        await ingestor.pause()
        do {
            try await ingestor.discardRetryBacklog()
            publishRuntimeState(.removed)
            endExclusive()
        } catch {
            publishRuntimeState(.unavailable)
            endExclusive()
            throw error
        }
    }

    private func resumeLocked() async {
        acceptsOperations = true
        isRewritePaused = false
        let shouldResume = shouldResumeAfterPause
        shouldResumeAfterPause = false
        guard shouldResume else { return }
        startMonitoringChanges()
        do {
            let authorization = await ingestor.authorizationStatus()
            _ = try await registerAndReconcileLocked(authorization: authorization)
        } catch RecordingPersistenceError.currentDeviceRemoved {
            return
        } catch {
            needsReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            Self.logger(attachments: [.error(error, name: "rollback-recovery-error")]) {
                .rollbackRecoveryFailed(description: error.localizedDescription)
            }
        }
    }

    private func registerAndReconcileLocked(
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        do {
            let snapshot = try await storeSnapshot()
            let epoch = snapshot.epoch
            let existing = snapshot.profiles.first(where: { $0.id == currentDevice.id })
            if let existing, let resetAt = snapshot.currentDeviceResetBarrier {
                try await store.perform(expectedDataEpochID: epoch.id) {
                    try await self.store.addRecordingDeviceRemoval(RecordingDeviceRemoval(
                        id: UUID(),
                        deviceID: existing.id,
                        removedAt: resetAt,
                        removedByDeviceID: self.currentDevice.id,
                    ))
                }
                return try await reconcileLocked(authorization: authorization)
            }
            let expected = expectedProfile(
                registrationEpochID: existing?.registrationEpochID ?? epoch.id,
            )
            if existing != expected {
                try await store.perform(expectedDataEpochID: epoch.id) {
                    try await self.store.addRecordingDeviceProfile(expected)
                }
            }
            return try await reconcileLocked(authorization: authorization)
        } catch RecordingPersistenceError.currentDeviceRemoved {
            throw RecordingPersistenceError.currentDeviceRemoved(currentDevice.id)
        } catch {
            needsReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            throw error
        }
    }

    private func reconcileOrFailClosed(
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        do {
            return try await reconcileLocked(authorization: authorization)
        } catch RecordingPersistenceError.currentDeviceRemoved {
            throw RecordingPersistenceError.currentDeviceRemoved(currentDevice.id)
        } catch {
            needsReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            throw error
        }
    }

    private func discardRetryBacklogForOffChoice() async throws {
        await ingestor.revokeRecordingAuthorization()
        do {
            try await ingestor.discardRetryBacklog()
            pendingOffCleanup = false
        } catch {
            pendingOffCleanup = true
            needsReconciliation = true
            publishRuntimeState(.unavailable)
            throw error
        }
    }

    private func reconcileLocked(
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        if pendingOffCleanup {
            try await discardRetryBacklogForOffChoice()
        }
        let snapshot = try await storeSnapshot()
        guard let profile = snapshot.profiles.first(where: { $0.id == currentDevice.id }) else {
            throw RecordingPersistenceError.currentDeviceNotRegistered(currentDevice.id)
        }
        let removal = snapshot.removals
            .filter { $0.deviceID == currentDevice.id }
            .min { $0.removedAt < $1.removedAt }

        await ingestor.revokeRecordingAuthorization()
        if removal != nil {
            try await ingestor.discardRetryBacklog()
            needsReconciliation = false
            publishRuntimeState(.removed)
            throw RecordingPersistenceError.currentDeviceRemoved(currentDevice.id)
        }

        let epoch = snapshot.epoch
        if preparedEpochID != epoch.id {
            try await ingestor.discardRetryBacklog()
            preparedEpochID = epoch.id
        }

        let status: RecordingDeviceStatus = if automaticRecordingEnabled {
            authorization.allowsBackgroundTracking ? .recording : .permissionRequired
        } else {
            .off
        }
        if automaticRecordingEnabled {
            try await ingestor.prepareRetryBacklog()
            let effectiveAt = max(enabledAt ?? registeredAt, epoch.changedAt)
            if authorization.allowsBackgroundTracking {
                try await ingestor.start(effectiveAt: effectiveAt, dataEpochID: epoch.id)
            } else {
                try await ingestor.authorizeRecording(
                    effectiveAt: effectiveAt,
                    dataEpochID: epoch.id,
                )
                await ingestor.stop()
            }
        } else {
            try await ingestor.discardRetryBacklog()
        }

        // Publish advisory status only after the physical transition succeeds. If the write
        // fails, the caller revokes recording again rather than advertising an uncommitted state.
        let existing = snapshot.checkIns.first { $0.deviceID == currentDevice.id }
        let checkInDate = now()
        let checkInDue = existing.map {
            checkInDate.timeIntervalSince($0.lastSeenAt) >= Self.checkInInterval
        } ?? true
        let checkIn: RecordingDeviceCheckIn
        if existing?.status != status || checkInDue {
            checkIn = try RecordingDeviceCheckIn(
                deviceID: currentDevice.id,
                revision: Self.nextRevision(after: existing?.revision, for: currentDevice.id),
                lastSeenAt: checkInDate,
                status: status,
            )
            try await store.perform(expectedDataEpochID: epoch.id) {
                try await self.store.setRecordingDeviceCheckIn(checkIn)
            }
        } else if let existing {
            checkIn = existing
        } else {
            preconditionFailure("A required recording check-in was not created.")
        }

        let configuration = RecordingDeviceConfiguration(
            device: RecordingDevice(
                profile: profile,
                nicknameChange: Self.latestMetadata(
                    for: currentDevice.id,
                    field: .nickname,
                    in: snapshot.metadataChanges,
                ),
                checkIn: checkIn,
                removal: nil,
            ),
            isCurrentDevice: true,
            localAutomaticRecordingEnabled: automaticRecordingEnabled,
        )
        needsReconciliation = false
        publishRuntimeState(.applied(configuration))
        return configuration
    }

    private func configurationsLocked(
        includeRemoved: Bool,
    ) async throws -> [RecordingDeviceConfiguration] {
        try await store.recordingDevices()
            .filter { includeRemoved || $0.removedAt == nil || $0.id == currentDevice.id }
            .map { device in
                let isCurrent = device.id == currentDevice.id
                return RecordingDeviceConfiguration(
                    device: device,
                    isCurrentDevice: isCurrent,
                    localAutomaticRecordingEnabled: isCurrent ? automaticRecordingEnabled : nil,
                )
            }
            .sorted { lhs, rhs in
                if lhs.isCurrentDevice { return true }
                if rhs.isCurrentDevice { return false }
                if lhs.device.lastSeenAt != rhs.device.lastSeenAt {
                    return lhs.device.lastSeenAt > rhs.device.lastSeenAt
                }
                return lhs.id.storeURL.absoluteString < rhs.id.storeURL.absoluteString
            }
    }

    private func applyObservedChange() async {
        await beginExclusive()
        guard acceptsOperations else {
            endExclusive()
            return
        }
        do {
            let snapshot = try await storeSnapshot()
            let currentCheckIn = snapshot.checkIns.first { $0.deviceID == currentDevice.id }
            let removalExists = snapshot.removals.contains { $0.deviceID == currentDevice.id }
            let heartbeatDue = currentCheckIn.map {
                now().timeIntervalSince($0.lastSeenAt) >= Self.checkInInterval
            } ?? true
            let expectedStatus: RecordingDeviceStatus = await automaticRecordingEnabled
                ? ((ingestor.authorizationStatus()).allowsBackgroundTracking
                    ? .recording : .permissionRequired)
                : .off
            let profileMatches = snapshot.profiles.first(where: { $0.id == currentDevice.id }).map {
                $0 == expectedProfile(registrationEpochID: $0.registrationEpochID)
            } ?? false
            if needsReconciliation || removalExists || heartbeatDue
                || currentCheckIn?.status != expectedStatus || !profileMatches
            {
                let authorization = await ingestor.authorizationStatus()
                _ = try await registerAndReconcileLocked(authorization: authorization)
            }
        } catch RecordingPersistenceError.currentDeviceRemoved {
            // `reconcileLocked` already stopped ingestion and published the terminal state.
        } catch {
            needsReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            Self.logger(attachments: [.error(error, name: "policy-observation-error")]) {
                .policyObservationFailed(description: error.localizedDescription)
            }
        }
        endExclusive()
    }

    private func storeSnapshot() async throws -> StoreSnapshot {
        try await store.readSnapshot {
            async let epoch = store.dataEpoch()
            async let profiles = store.recordingDeviceProfiles()
            async let metadataChanges = store.recordingDeviceMetadataChanges()
            async let checkIns = store.recordingDeviceCheckIns()
            async let removals = store.recordingDeviceRemovals()
            let values = try await (epoch, profiles, metadataChanges, checkIns, removals)
            let currentProfile = values.1.first { $0.id == currentDevice.id }
            let resetBarrier: Date? = if let currentProfile {
                try await store.recordingDeviceResetBarrier(
                    for: currentProfile.registrationEpochID,
                )
            } else {
                nil
            }
            return StoreSnapshot(
                epoch: values.0,
                profiles: values.1,
                metadataChanges: values.2,
                checkIns: values.3,
                removals: values.4,
                currentDeviceResetBarrier: resetBarrier,
            )
        }
    }

    private func expectedProfile(
        registrationEpochID: WhereDataEpochID,
    ) -> RecordingDeviceProfile {
        RecordingDeviceProfile(
            id: currentDevice.id,
            systemName: currentDevice.systemName,
            kind: currentDevice.kind,
            registeredAt: registeredAt,
            registrationEpochID: registrationEpochID,
        )
    }

    private static func latestMetadata(
        for deviceID: RecordingDeviceID,
        field: RecordingDeviceMetadataField,
        in changes: [RecordingDeviceMetadataChange],
    ) -> RecordingDeviceMetadataChange? {
        changes
            .filter { $0.deviceID == deviceID && $0.field == field }
            .max(by: RecordingDeviceMetadataChange.isOrderedBefore)
    }

    private static func nextRevision(
        after revision: Int64?,
        for deviceID: RecordingDeviceID,
    ) throws -> Int64 {
        guard let revision else { return 0 }
        let (next, overflow) = revision.addingReportingOverflow(1)
        guard !overflow else { throw RecordingPersistenceError.revisionExhausted(deviceID) }
        return next
    }

    private func publishRuntimeState(_ state: RecordingDeviceRuntimeState) {
        let update = RecordingDeviceRuntimeUpdate(sequence: nextRuntimeSequence, state: state)
        let (next, overflow) = nextRuntimeSequence.addingReportingOverflow(1)
        precondition(overflow == false, "Recording runtime sequence exhausted UInt64.")
        nextRuntimeSequence = next
        latestRuntimeUpdate = update
        configurationBroadcaster.send(update)
    }

    private func requireActive() throws {
        guard acceptsOperations else { throw CancellationError() }
    }

    private func beginExclusive() async {
        if isExclusive {
            await withCheckedContinuation { continuation in waiters.append(continuation) }
        } else {
            isExclusive = true
        }
    }

    private func endExclusive() {
        if waiters.isEmpty {
            isExclusive = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
