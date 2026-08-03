import Foundation

/// Owns recording-device registration, desired-policy commands, and this installation's
/// physical GPS reconciliation.
///
/// The controller deliberately persists three independently owned device records: an immutable
/// profile created by the installation, append-only nickname events authored from any device,
/// and a target-owned check-in. Desired authority (On, Off, or archived) is one append-only event
/// stream.
/// Keeping those writers apart prevents CloudKit's last-writer-wins merge from rolling unrelated
/// fields backward.
///
/// Registration is one explicit lifecycle operation. Reads and later commands never accept or
/// infer an initial preference, so synced policy is the only authority after registration. A
/// focused store observer compares the current installation's effective authority and check-in.
/// Unrelated sample or region writes do not repeatedly reconcile GPS except when a heartbeat
/// is due.
public actor DeviceRecordingController {
    private let store: any WhereStore
    private let ingestor: LocationIngestor
    public nonisolated let currentDevice: CurrentRecordingDevice
    private let now: @Sendable () -> Date
    private let onPolicyChanged: @Sendable () async -> Void
    private let registeredAt: Date
    private let initialRecordingChoice: InstallationRecordingContext.InitialRecordingChoice
    private let configurationBroadcaster = RecordingConfigurationBroadcaster()

    /// Reentrancy-safe gate held across store and physical-ingestor awaits. Actor isolation alone
    /// is insufficient because another command can enter while an actor method is suspended.
    private var isExclusive = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var acceptsOperations = true
    /// Whether this stack has entered the recording lifecycle. A scope created only to restore
    /// onboarding data has not: backup completion must not invent authority that did not exist
    /// before the reversible import pause.
    private var recordingLifecycleStarted = false
    /// Snapshot consumed by the matching resume path after a reversible pause.
    private var shouldResumeAuthorityAfterPause = false
    /// Prevents two reset/import lifecycles from interleaving across their actor awaits.
    private var isRewritePaused = false

    private var policyObservationTask: Task<Void, Never>?
    /// Exact policy event most recently applied and acknowledged on this installation.
    private var lastAppliedCurrentPolicyID: UUID?
    /// Retained after fail-closed reconciliation so any later store ping retries it.
    private var needsPolicyReconciliation = false
    private var nextRuntimeSequence: UInt64 = 0
    private var latestRuntimeUpdate: RecordingDeviceRuntimeUpdate?

    private static let checkInInterval: TimeInterval = 15 * 60

    private static let logger = WhereLog.root(DeviceRecordingControllerLog.self)

    /// Epoch-pinned recording tables used to make one authority decision. A reset/Replace that
    /// lands while these tables are loading makes the snapshot throw instead of combining old
    /// policy with new-epoch check-ins.
    private struct StoreSnapshot {
        let epoch: WhereDataEpoch
        let profiles: [RecordingDeviceProfile]
        let metadataChanges: [RecordingDeviceMetadataChange]
        let checkIns: [RecordingDeviceCheckIn]
        let policyChanges: [RecordingPolicyChange]
    }

    init(
        store: any WhereStore,
        ingestor: LocationIngestor,
        installationContext: InstallationRecordingContext,
        now: @escaping @Sendable () -> Date,
        onPolicyChanged: @escaping @Sendable () async -> Void,
    ) {
        self.store = store
        self.ingestor = ingestor
        guard let initialRecordingChoice = installationContext.initialRecordingChoice else {
            preconditionFailure("Recording services require a confirmed installation context.")
        }
        currentDevice = installationContext.currentDevice
        registeredAt = installationContext.registeredAt
        self.initialRecordingChoice = initialRecordingChoice
        self.now = now
        self.onPolicyChanged = onPolicyChanged
    }

    deinit {
        policyObservationTask?.cancel()
        configurationBroadcaster.finishAll()
    }

    /// Applied current-installation states, emitted only after acknowledgement is durable.
    public nonisolated func runtimeUpdates()
        -> AsyncStream<RecordingDeviceRuntimeUpdate>
    {
        configurationBroadcaster.subscribe()
    }

    /// Latest controller-ordered runtime state, for a caller that needs to synchronize after an
    /// awaited command without racing a newer emission already queued on the async stream.
    public func currentRuntimeUpdate() -> RecordingDeviceRuntimeUpdate? {
        latestRuntimeUpdate
    }

    /// Start the focused policy observer. Safe to call repeatedly from lifecycle setup.
    public func startMonitoringPolicyChanges() {
        recordingLifecycleStarted = true
        guard policyObservationTask == nil else { return }
        let updates = store.changes()
        policyObservationTask = Task { [weak self] in
            for await _ in updates {
                guard let self else { break }
                await applyObservedPolicyChange()
            }
        }
    }

    /// Register this installation and its confirmed initial choice exactly once, then apply it.
    /// `initialPolicyChangeID` comes from the non-backed-up installation context, making a retry
    /// idempotent even if profile and policy records are observed at different times.
    @discardableResult
    public func register(
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        recordingLifecycleStarted = true
        do {
            try await registerLocked(
                initialPolicyChangeID: initialRecordingChoice.policyChangeID,
                initialEnabled: initialRecordingChoice.isEnabled,
            )
            let reconciliation = try await reconcileLocked(authorization: authorization)
            lastAppliedCurrentPolicyID = reconciliation.latestPolicyChangeID
            needsPolicyReconciliation = false
            return reconciliation
        } catch {
            needsPolicyReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            throw error
        }
    }

    /// Register the immutable first choice, then apply the user's current onboarding selection
    /// before opening physical recording authority. This differs only on a retry after the first
    /// choice was already persisted: the immutable event stays intact and the new selection is a
    /// causal follow-up command, instead of silently snapping the UI back to the earlier choice.
    @discardableResult
    public func registerForOnboarding(
        desiredEnabled: Bool,
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        recordingLifecycleStarted = true
        do {
            try await registerLocked(
                initialPolicyChangeID: initialRecordingChoice.policyChangeID,
                initialEnabled: initialRecordingChoice.isEnabled,
            )
            let snapshot = try await storeSnapshot()
            let timeline = Self.policyTimeline(
                for: currentDevice.id,
                in: snapshot.policyChanges,
            )
            guard Self.hasCompleteRevisionHistory(timeline),
                  let latestPolicy = RecordingPolicyChange.canonicalHead(in: timeline)
            else {
                throw RecordingPersistenceError.currentDevicePolicyUnknown(currentDevice.id)
            }
            let commandDate = now()
            let desiredState: RecordingPolicyState = desiredEnabled ? .on : .off
            let policyChange: RecordingPolicyChange? = if latestPolicy.state == desiredState {
                nil
            } else {
                try RecordingPolicyChange.appendingCommand(
                    to: timeline,
                    deviceID: currentDevice.id,
                    issuedAt: commandDate,
                    issuedByDeviceID: currentDevice.id,
                    effectiveAt: Self.nextEffectiveDate(
                        proposed: max(commandDate, snapshot.epoch.changedAt),
                        after: latestPolicy,
                    ),
                    state: desiredState,
                    reason: .userCommand,
                )
            }
            if let policyChange {
                try await store.perform(expectedDataEpochID: snapshot.epoch.id) {
                    try await self.store.addRecordingPolicyChange(policyChange)
                }
                // Historical visibility changed as soon as the authority event committed. Do
                // not make derived reconciliation depend on a later physical/check-in success.
                await onPolicyChanged()
            }

            let reconciliation = try await reconcileLocked(authorization: authorization)
            lastAppliedCurrentPolicyID = reconciliation.latestPolicyChangeID
            needsPolicyReconciliation = false
            return reconciliation
        } catch {
            needsPolicyReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            throw error
        }
    }

    /// Apply the latest synced policy to this installation. Failure is fail-closed: GPS is
    /// stopped before the error is surfaced, so stale local preference can never authorize a fix.
    @discardableResult
    public func reconcile(
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        recordingLifecycleStarted = true
        do {
            let reconciliation = try await reconcileLocked(authorization: authorization)
            lastAppliedCurrentPolicyID = reconciliation.latestPolicyChangeID
            needsPolicyReconciliation = false
            return reconciliation
        } catch {
            needsPolicyReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            throw error
        }
    }

    /// Pure read of active device configurations. A profile whose policy has not arrived yet is
    /// returned with `.unknown` policy rather than fabricated as enabled.
    public func devices() async throws -> [RecordingDeviceConfiguration] {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        return try await configurationsLocked(includeArchived: false)
    }

    /// Append a desired-state command. A command for this installation is physically reconciled
    /// and acknowledged before returning; a remote command remains pending until its target syncs.
    @discardableResult
    public func setEnabled(
        _ enabled: Bool,
        for deviceID: RecordingDeviceID,
    ) async throws -> [RecordingDeviceConfiguration] {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()

        let snapshot = try await storeSnapshot()
        guard snapshot.profiles.contains(where: { $0.id == deviceID }) else {
            throw RecordingPersistenceError.deviceNotFound(deviceID)
        }
        let epoch = snapshot.epoch
        let timeline = Self.policyTimeline(for: deviceID, in: snapshot.policyChanges)
        guard Self.hasCompleteRevisionHistory(timeline),
              let latestPolicy = Self.effectivePolicy(
                  for: deviceID,
                  epoch: epoch,
                  timeline: timeline,
              )
        else {
            throw RecordingPersistenceError.devicePolicyUnknown(deviceID)
        }
        let issuedAt = now()
        let desiredState: RecordingPolicyState = enabled ? .on : .off
        let causalHead = RecordingPolicyChange.canonicalHead(in: timeline)
        let policyChange: RecordingPolicyChange? = if latestPolicy.state == desiredState {
            nil
        } else {
            try RecordingPolicyChange.appendingCommand(
                to: timeline,
                deviceID: deviceID,
                issuedAt: issuedAt,
                issuedByDeviceID: currentDevice.id,
                effectiveAt: Self.nextEffectiveDate(
                    proposed: max(issuedAt, epoch.changedAt),
                    after: causalHead,
                ),
                state: desiredState,
                reason: .userCommand,
            )
        }

        guard let policyChange else {
            if deviceID == currentDevice.id {
                if !enabled {
                    await ingestor.revokeRecordingAuthorization()
                }
                try await reconcileCurrentAfterCommandLocked()
            }
            return try await configurationsLocked(includeArchived: false)
        }

        try await store.perform(expectedDataEpochID: epoch.id) {
            try await self.store.addRecordingPolicyChange(policyChange)
        }
        // Close local physical authority before any potentially slow derived-data rebuild. The
        // durable cutoff already hides history, but raw fixes must not continue entering the
        // store/outbox after the user turns this installation Off.
        if deviceID == currentDevice.id, !enabled {
            await ingestor.revokeRecordingAuthorization()
        }
        // The cutoff is already durable even if physical acknowledgement below fails.
        await onPolicyChanged()

        if deviceID == currentDevice.id {
            try await reconcileCurrentAfterCommandLocked()
        }
        return try await configurationsLocked(includeArchived: false)
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
        let changes = snapshot.metadataChanges
        let latest = Self.latestMetadata(for: deviceID, field: .nickname, in: changes)
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNickname = trimmed.isEmpty ? nil : trimmed
        guard latest?.nickname != resolvedNickname else {
            return try await configurationsLocked(includeArchived: false)
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
        return try await configurationsLocked(includeArchived: false)
    }

    /// Hide a non-current device and append an Off policy atomically. History and raw samples
    /// remain in the event log and backups.
    public func archive(
        _ deviceID: RecordingDeviceID,
    ) async throws -> [RecordingDeviceConfiguration] {
        precondition(deviceID != currentDevice.id, "The current device cannot archive itself.")
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        let snapshot = try await storeSnapshot()
        guard snapshot.profiles.contains(where: { $0.id == deviceID }) else {
            throw RecordingPersistenceError.deviceNotFound(deviceID)
        }

        let date = now()
        let epoch = snapshot.epoch
        let timeline = Self.policyTimeline(for: deviceID, in: snapshot.policyChanges)
        guard Self.hasCompleteRevisionHistory(timeline),
              let latestPolicy = Self.effectivePolicy(
                  for: deviceID,
                  epoch: epoch,
                  timeline: timeline,
              )
        else {
            throw RecordingPersistenceError.devicePolicyUnknown(deviceID)
        }
        let causalHead = RecordingPolicyChange.canonicalHead(in: timeline)
        let policyChange: RecordingPolicyChange? = if latestPolicy.state != .archived {
            try RecordingPolicyChange.appendingCommand(
                to: timeline,
                deviceID: deviceID,
                issuedAt: date,
                issuedByDeviceID: currentDevice.id,
                effectiveAt: Self.nextEffectiveDate(
                    proposed: max(date, epoch.changedAt),
                    after: causalHead,
                ),
                state: .archived,
                reason: .archive,
            )
        } else {
            nil
        }
        guard let policyChange else {
            return try await configurationsLocked(includeArchived: false)
        }
        try await store.perform(expectedDataEpochID: epoch.id) {
            try await self.store.addRecordingPolicyChange(policyChange)
        }
        await onPolicyChanged()
        return try await configurationsLocked(includeArchived: false)
    }

    /// Reversibly close this stack around a backup import or reset transaction. Pending samples
    /// remain owned by the installation until the destructive operation actually commits.
    func pause() async throws {
        await beginExclusive()
        defer { endExclusive() }
        guard !isRewritePaused else {
            throw RecordingPersistenceError.recordingRewriteInProgress
        }
        isRewritePaused = true
        shouldResumeAuthorityAfterPause = shouldResumeAuthorityAfterPause
            || recordingLifecycleStarted
        recordingLifecycleStarted = false
        acceptsOperations = false
        policyObservationTask?.cancel()
        policyObservationTask = nil
        await ingestor.pause()
    }

    /// Reopen a stack retained after a failed reset.
    func resumeAfterFailedReset() async {
        await beginExclusive()
        defer { endExclusive() }
        await resumeLocked()
    }

    /// Reopen the old authority after a backup-import transaction rolls back.
    func resumeAfterImportRollback() async {
        await beginExclusive()
        defer { endExclusive() }
        await resumeLocked()
    }

    private func resumeLocked() async {
        acceptsOperations = true
        isRewritePaused = false
        let shouldResumeAuthority = shouldResumeAuthorityAfterPause
        shouldResumeAuthorityAfterPause = false
        guard shouldResumeAuthority else { return }
        startMonitoringPolicyChanges()
        do {
            try await registerLocked(
                initialPolicyChangeID: initialRecordingChoice.policyChangeID,
                initialEnabled: initialRecordingChoice.isEnabled,
            )
            let authorization = await ingestor.authorizationStatus()
            let reconciliation = try await reconcileLocked(authorization: authorization)
            lastAppliedCurrentPolicyID = reconciliation.latestPolicyChangeID
            needsPolicyReconciliation = false
        } catch {
            needsPolicyReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            Self.logger(attachments: [.error(error, name: "rollback-recovery-error")]) {
                .rollbackRecoveryFailed(description: error.localizedDescription)
            }
        }
    }

    /// Reactivate after a committed backup import, restore this installation's fixed
    /// registration, and apply imported authority. Import data is already committed at this
    /// point. Privacy-critical sidecar cleanup throws so the coordinator can report committed
    /// partial success; later physical recovery remains fail-closed and logged for retry.
    func resumeAfterImport(discardPendingSamples: Bool) async throws {
        await beginExclusive()
        acceptsOperations = true
        let shouldResumeAuthority = shouldResumeAuthorityAfterPause
        if discardPendingSamples {
            do {
                try await ingestor.discardRetryBacklog()
            } catch {
                // The import is already committed. Keep the old installation context and
                // recording stack paused so a retry can remove the same sidecar safely.
                isRewritePaused = false
                acceptsOperations = false
                needsPolicyReconciliation = true
                publishRuntimeState(.unavailable)
                endExclusive()
                throw error
            }
        }
        shouldResumeAuthorityAfterPause = false
        isRewritePaused = false
        guard shouldResumeAuthority else {
            endExclusive()
            return
        }
        startMonitoringPolicyChanges()
        do {
            try await registerLocked(
                initialPolicyChangeID: initialRecordingChoice.policyChangeID,
                initialEnabled: initialRecordingChoice.isEnabled,
            )
            let authorization = await ingestor.authorizationStatus()
            let reconciliation = try await reconcileLocked(authorization: authorization)
            lastAppliedCurrentPolicyID = reconciliation.latestPolicyChangeID
            needsPolicyReconciliation = false
            endExclusive()
        } catch {
            needsPolicyReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            endExclusive()
            Self.logger(attachments: [.error(error, name: "import-recovery-error")]) {
                .importRecoveryFailed(description: error.localizedDescription)
            }
        }
    }

    /// Finish a committed reset without reopening this installation's authority. A failed
    /// sidecar cleanup leaves the old installation fail-closed; the destructive data epoch makes
    /// a later retry clear the same backlog before acknowledgement.
    func finishReset() async throws {
        await beginExclusive()
        do {
            try await ingestor.discardRetryBacklog()
        } catch {
            isRewritePaused = false
            needsPolicyReconciliation = true
            publishRuntimeState(.unavailable)
            endExclusive()
            throw error
        }
        shouldResumeAuthorityAfterPause = false
        isRewritePaused = false
        endExclusive()
    }

    private func registerLocked(
        initialPolicyChangeID: UUID,
        initialEnabled: Bool,
    ) async throws {
        let snapshot = try await storeSnapshot()
        let epoch = snapshot.epoch
        let existingProfile = snapshot.profiles.first(where: { $0.id == currentDevice.id })
        let profile = expectedProfile(
            registrationEpochID: existingProfile?.registrationEpochID ?? epoch.id,
        )
        let ownsInitialPolicyInThisEpoch = existingProfile == nil
            || existingProfile?.registrationEpochID == epoch.id
        let initialPolicy = expectedInitialPolicy(
            id: initialPolicyChangeID,
            isEnabled: initialEnabled,
            in: epoch,
        )
        let existingInitialPolicy = snapshot.policyChanges
            .first(where: { $0.id == initialPolicyChangeID })
        let needsProfileWrite = existingProfile != profile
        let needsInitialPolicyWrite = ownsInitialPolicyInThisEpoch
            && existingInitialPolicy != initialPolicy
        guard needsProfileWrite || needsInitialPolicyWrite else { return }

        // The add APIs validate identical immutable retries and reject conflicting payloads.
        // An installation first seen in this epoch also retries its immutable initial policy.
        // An existing profile entering a newer destructive epoch must not replay that old first
        // choice: the epoch's fail-closed default remains authoritative until a new command.
        try await store.perform(expectedDataEpochID: epoch.id) {
            try await self.store.addRecordingDeviceProfile(profile)
            if ownsInitialPolicyInThisEpoch {
                try await self.store.addRecordingPolicyChange(initialPolicy)
            }
        }
    }

    private func reconcileCurrentAfterCommandLocked() async throws {
        do {
            let authorization = await ingestor.authorizationStatus()
            let reconciliation = try await reconcileLocked(authorization: authorization)
            lastAppliedCurrentPolicyID = reconciliation.latestPolicyChangeID
            needsPolicyReconciliation = false
        } catch {
            needsPolicyReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            throw error
        }
    }

    private func reconcileLocked(
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        let snapshot = try await storeSnapshot()
        guard let profile = snapshot.profiles.first(where: { $0.id == currentDevice.id }) else {
            throw RecordingPersistenceError.currentDeviceNotRegistered(currentDevice.id)
        }
        let epoch = snapshot.epoch
        let policies = snapshot.policyChanges
        let timeline = Self.policyTimeline(for: currentDevice.id, in: policies)
        guard Self.hasCompleteRevisionHistory(timeline) else {
            throw RecordingPersistenceError.incompletePolicyHistory(currentDevice.id)
        }
        guard let latest = Self.effectivePolicy(
            for: currentDevice.id,
            epoch: epoch,
            timeline: timeline,
        ) else {
            throw RecordingPersistenceError.currentDevicePolicyUnknown(currentDevice.id)
        }
        let nickname = Self.latestMetadata(
            for: currentDevice.id,
            field: .nickname,
            in: snapshot.metadataChanges,
        )

        let existing = snapshot.checkIns
            .first(where: { $0.deviceID == currentDevice.id })
        let requiredCleanupToken: RecordingPolicyCleanupToken? = if epoch.isDestructive {
            RecordingPolicyCleanupToken(rawValue: epoch.id.rawValue)
        } else {
            Self.destructiveCleanupToken(
                for: currentDevice.id,
                in: policies,
            )
        }

        // Close the sample gate before computing or acknowledging authority. In particular,
        // `authorizeRecording` restores and drains the durable outbox, so it cannot run until
        // the check-in proving this policy was applied has committed.
        await ingestor.revokeRecordingAuthorization()
        if existing?.lastDiscardedPolicyFrontierToken != requiredCleanupToken,
           requiredCleanupToken != nil
        {
            try await ingestor.discardRetryBacklog()
        }
        if latest.isEnabled {
            try await ingestor.prepareRetryBacklog()
        }

        let status: RecordingDeviceStatus = if latest.isEnabled {
            authorization.allowsBackgroundTracking ? .recording : .permissionRequired
        } else {
            .off
        }

        let checkInDate = now()
        let needsAcknowledgement = existing?.lastAppliedPolicyChangeID != latest.id
            || existing?.lastDiscardedPolicyFrontierToken != requiredCleanupToken
            || existing?.status != status
        let needsPeriodicCheckIn = existing.map {
            checkInDate.timeIntervalSince($0.lastSeenAt) >= Self.checkInInterval
        } ?? true
        let checkIn: RecordingDeviceCheckIn
        if needsAcknowledgement || needsPeriodicCheckIn {
            checkIn = try RecordingDeviceCheckIn(
                deviceID: currentDevice.id,
                revision: Self.nextRevision(
                    after: existing?.revision,
                    for: currentDevice.id,
                ),
                lastSeenAt: checkInDate,
                appliedAt: needsAcknowledgement ? checkInDate :
                    (existing?.appliedAt ?? checkInDate),
                lastAppliedPolicyChangeID: latest.id,
                lastDiscardedPolicyFrontierToken: requiredCleanupToken,
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

        // Only a durable acknowledgement opens physical authority. This ordering also prevents
        // an outbox drain from committing samples when the check-in write fails.
        if latest.isEnabled {
            if authorization.allowsBackgroundTracking {
                try await ingestor.start(
                    effectiveAt: latest.effectiveAt,
                    dataEpochID: epoch.id,
                )
            } else {
                // Keep foreground fill-in fixes authorized for When-In-Use while pausing
                // background monitoring.
                try await ingestor.authorizeRecording(
                    effectiveAt: latest.effectiveAt,
                    dataEpochID: epoch.id,
                )
                await ingestor.stop()
            }
        }

        let configuration = RecordingDeviceConfiguration(
            device: RecordingDevice(
                profile: profile,
                nicknameChange: nickname,
                checkIn: checkIn,
                policyChange: latest,
            ),
            policyChange: latest,
            requiredCleanupToken: requiredCleanupToken,
        )
        publishRuntimeState(.applied(configuration))
        return configuration
    }

    private func configurationsLocked(
        includeArchived: Bool,
    ) async throws -> [RecordingDeviceConfiguration] {
        try await store.readSnapshot {
            async let devices = store.recordingDevices()
            async let policies = store.recordingPolicyChanges()
            async let epoch = store.dataEpoch()
            let (resolvedDevices, resolvedPolicies, resolvedEpoch) = try await (
                devices,
                policies,
                epoch,
            )
            return resolvedDevices
                .map { device in
                    let timeline = Self.policyTimeline(for: device.id, in: resolvedPolicies)
                    guard Self.hasCompleteRevisionHistory(timeline),
                          let latest = Self.effectivePolicy(
                              for: device.id,
                              epoch: resolvedEpoch,
                              timeline: timeline,
                          )
                    else {
                        return RecordingDeviceConfiguration(device: device, policy: .unknown)
                    }
                    return RecordingDeviceConfiguration(
                        device: device,
                        policyChange: latest,
                        requiredCleanupToken: resolvedEpoch.isDestructive
                            ? RecordingPolicyCleanupToken(rawValue: resolvedEpoch.id.rawValue)
                            : Self.destructiveCleanupToken(
                                for: device.id,
                                in: resolvedPolicies,
                            ),
                    )
                }
                .filter {
                    includeArchived || !$0.isArchived || $0.id == currentDevice.id
                }
                .sorted { lhs, rhs in
                    if lhs.id == currentDevice.id { return true }
                    if rhs.id == currentDevice.id { return false }
                    if lhs.device.lastSeenAt != rhs.device.lastSeenAt {
                        return lhs.device.lastSeenAt > rhs.device.lastSeenAt
                    }
                    return lhs.id.storeURL.absoluteString < rhs.id.storeURL.absoluteString
                }
        }
    }

    private func applyObservedPolicyChange() async {
        await beginExclusive()
        guard acceptsOperations else {
            endExclusive()
            return
        }
        do {
            let snapshot = try await storeSnapshot()
            let epoch = snapshot.epoch
            let policies = snapshot.policyChanges
            let checkIns = snapshot.checkIns
            let existingProfile = snapshot.profiles.first { $0.id == currentDevice.id }
            let hasExpectedProfile = existingProfile.map {
                $0 == expectedProfile(registrationEpochID: $0.registrationEpochID)
            } ?? false
            let requiresInitialPolicy = existingProfile?.registrationEpochID == epoch.id
            let hasExpectedInitialPolicy = !requiresInitialPolicy || policies
                .contains(expectedInitialPolicy(
                    id: initialRecordingChoice.policyChangeID,
                    isEnabled: initialRecordingChoice.isEnabled,
                    in: epoch,
                ))
            let timeline = Self.policyTimeline(for: currentDevice.id, in: policies)
            let latestCurrentPolicyID = Self.effectivePolicy(
                for: currentDevice.id,
                epoch: epoch,
                timeline: timeline,
            )?.id
            let requiredCleanupToken: RecordingPolicyCleanupToken? = epoch.isDestructive
                ? RecordingPolicyCleanupToken(rawValue: epoch.id.rawValue)
                : Self.destructiveCleanupToken(
                    for: currentDevice.id,
                    in: policies,
                )
            let acknowledgedCurrentPolicyID = checkIns.first(where: {
                $0.deviceID == currentDevice.id
            })?.lastAppliedPolicyChangeID
            let currentCheckIn = checkIns.first { $0.deviceID == currentDevice.id }
            let acknowledgedCleanupToken = currentCheckIn?
                .lastDiscardedPolicyFrontierToken
            let heartbeatDue = currentCheckIn.map {
                now().timeIntervalSince($0.lastSeenAt) >= Self.checkInInterval
            } ?? true
            let shouldReconcile = needsPolicyReconciliation
                || !hasExpectedProfile
                || !hasExpectedInitialPolicy
                || latestCurrentPolicyID != lastAppliedCurrentPolicyID
                || acknowledgedCurrentPolicyID != latestCurrentPolicyID
                || acknowledgedCleanupToken != requiredCleanupToken
                || heartbeatDue
            if shouldReconcile {
                try await registerLocked(
                    initialPolicyChangeID: initialRecordingChoice.policyChangeID,
                    initialEnabled: initialRecordingChoice.isEnabled,
                )
                let authorization = await ingestor.authorizationStatus()
                let reconciliation = try await reconcileLocked(authorization: authorization)
                lastAppliedCurrentPolicyID = reconciliation.latestPolicyChangeID
                needsPolicyReconciliation = false
            }
            endExclusive()
        } catch {
            needsPolicyReconciliation = true
            await ingestor.revokeRecordingAuthorization()
            publishRuntimeState(.unavailable)
            endExclusive()
            Self.logger(attachments: [.error(error, name: "policy-observation-error")]) {
                .policyObservationFailed(description: error.localizedDescription)
            }
        }
    }

    private func storeSnapshot() async throws -> StoreSnapshot {
        try await store.readSnapshot {
            async let epoch = store.dataEpoch()
            async let profiles = store.recordingDeviceProfiles()
            async let metadataChanges = store.recordingDeviceMetadataChanges()
            async let checkIns = store.recordingDeviceCheckIns()
            async let policyChanges = store.recordingPolicyChanges()
            let values = try await (
                epoch,
                profiles,
                metadataChanges,
                checkIns,
                policyChanges,
            )
            return StoreSnapshot(
                epoch: values.0,
                profiles: values.1,
                metadataChanges: values.2,
                checkIns: values.3,
                policyChanges: values.4,
            )
        }
    }

    private static func policyTimeline(
        for deviceID: RecordingDeviceID,
        in changes: [RecordingPolicyChange],
    ) -> [RecordingPolicyChange] {
        changes
            .filter { $0.deviceID == deviceID }
            .sorted(by: RecordingPolicyChange.isOrderedBefore)
    }

    /// A destructive epoch is a universal fail-closed authority event. Devices absent from the
    /// issuer's CloudKit snapshot therefore still resolve archived when their old profile arrives
    /// later; a new per-device command at revision zero can explicitly reopen them.
    private static func effectivePolicy(
        for deviceID: RecordingDeviceID,
        epoch: WhereDataEpoch,
        timeline: [RecordingPolicyChange],
    ) -> RecordingPolicyChange? {
        if let latest = RecordingPolicyChange.canonicalHead(in: timeline) { return latest }
        guard epoch.isDestructive, let issuer = epoch.changedByDeviceID else { return nil }
        let reason: RecordingPolicyReason = switch epoch.reason {
            case .initial: preconditionFailure("The initial epoch is not destructive.")
            case .accountReset: .accountReset
            case .backupReplace: .backupReplace
        }
        return RecordingPolicyChange(
            id: epoch.id.rawValue,
            deviceID: deviceID,
            parentIDs: [],
            revision: 0,
            issuedAt: epoch.changedAt,
            issuedByDeviceID: issuer,
            effectiveAt: epoch.changedAt,
            state: .archived,
            reason: reason,
        )
    }

    private static func destructiveCleanupToken(
        for deviceID: RecordingDeviceID,
        in changes: [RecordingPolicyChange],
    ) -> RecordingPolicyCleanupToken? {
        RecordingPolicyChange.destructiveCleanupToken(
            in: changes.filter { $0.deviceID == deviceID },
        )
    }

    /// A higher revision arriving before one of its predecessors, or a malformed reason/state
    /// pair, is not authority. Waiting for a valid complete timeline prevents a later On from
    /// opening and draining the outbox before an intervening destructive barrier arrives.
    private static func hasCompleteRevisionHistory(
        _ timeline: [RecordingPolicyChange],
    ) -> Bool {
        RecordingPolicyChange.formValidPersistedTimelines(timeline)
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

    private func expectedInitialPolicy(
        id: UUID,
        isEnabled: Bool,
        in epoch: WhereDataEpoch,
    ) -> RecordingPolicyChange {
        RecordingPolicyChange(
            id: id,
            deviceID: currentDevice.id,
            parentIDs: [],
            revision: 0,
            issuedAt: initialRecordingChoice.confirmedAt,
            issuedByDeviceID: currentDevice.id,
            effectiveAt: max(initialRecordingChoice.confirmedAt, epoch.changedAt),
            state: isEnabled ? .on : .off,
            reason: .initialRegistration,
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
        guard !overflow else {
            throw RecordingPersistenceError.revisionExhausted(deviceID)
        }
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

    /// Keep historical cutoffs monotonic for a writer whose wall clock moves backward. Causal
    /// ordering is carried separately by `revision`, so equal cutoffs need no timestamp mutation.
    private static func nextEffectiveDate(
        proposed: Date,
        after latest: RecordingPolicyChange?,
    ) -> Date {
        guard let latest else { return proposed }
        return max(proposed, latest.effectiveAt)
    }

    private func requireActive() throws {
        guard acceptsOperations else { throw CancellationError() }
    }

    private func beginExclusive() async {
        if isExclusive {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
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
