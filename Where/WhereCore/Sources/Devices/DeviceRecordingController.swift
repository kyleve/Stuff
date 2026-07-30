import Foundation

/// Serializes the synced recording policy with this device's physical GPS
/// lifecycle.
///
/// Policy writes take effect historically at their timestamp immediately on
/// every device that has synced them. The target device later acknowledges the
/// latest event after it has started or stopped its local `LocationIngestor`.
public actor DeviceRecordingController {
    private let store: any WhereStore
    private let ingestor: LocationIngestor
    public nonisolated let currentDevice: CurrentRecordingDevice
    private let now: @Sendable () -> Date

    /// Reentrancy-safe gate: each public mutation/reconcile holds it across
    /// awaits, so a rapid toggle cannot let an older start finish after a newer
    /// stop. Actor isolation alone is insufficient because actors are reentrant.
    private var isExclusive = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var acceptsOperations = true

    init(
        store: any WhereStore,
        ingestor: LocationIngestor,
        currentDevice: CurrentRecordingDevice,
        now: @escaping @Sendable () -> Date,
    ) {
        self.store = store
        self.ingestor = ingestor
        self.currentDevice = currentDevice
        self.now = now
    }

    /// Register this installation if needed, migrate its initial desired state
    /// from local preferences, then make physical monitoring match the latest
    /// synced policy and authorization.
    @discardableResult
    public func reconcile(
        initialEnabled: Bool,
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        return try await reconcileLocked(
            initialEnabled: initialEnabled,
            authorization: authorization,
        )
    }

    /// Active device configurations, current device first and then by most
    /// recent check-in.
    public func devices(initialEnabled: Bool) async throws -> [RecordingDeviceConfiguration] {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        try await ensureCurrentDeviceLocked(initialEnabled: initialEnabled)
        return try await configurationsLocked(includeArchived: false)
    }

    /// Append a desired-state change. For this installation, reconcile and
    /// acknowledge it before returning. A remote installation will show pending
    /// until that device receives and applies the CloudKit row.
    @discardableResult
    public func setEnabled(
        _ enabled: Bool,
        for deviceID: RecordingDeviceID,
        initialEnabled: Bool,
    ) async throws -> [RecordingDeviceConfiguration] {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        try await ensureCurrentDeviceLocked(initialEnabled: initialEnabled)

        let device = try await store.recordingDevices().first(where: { $0.id == deviceID })
        let changes = try await store.recordingPolicyChanges()
        let change = RecordingPolicyChange(
            id: UUID(),
            deviceID: deviceID,
            effectiveAt: Self.nextEffectiveDate(
                proposed: now(),
                after: Self.latestPolicy(for: deviceID, in: changes),
            ),
            isEnabled: enabled,
        )
        try await store.perform {
            try await store.addRecordingPolicyChange(change)
            if enabled, let device, device.archivedAt != nil {
                try await store.setRecordingDevice(device.unarchived())
            }
        }

        if deviceID == currentDevice.id {
            let authorization = await ingestor.authorizationStatus()
            _ = try await reconcileLocked(
                initialEnabled: initialEnabled,
                authorization: authorization,
            )
        }
        return try await configurationsLocked(includeArchived: false)
    }

    /// Change the synced, user-editable nickname. Empty/whitespace-only text
    /// clears the nickname and falls back to the generic system label.
    public func rename(
        _ deviceID: RecordingDeviceID,
        to nickname: String,
        initialEnabled: Bool,
    ) async throws -> [RecordingDeviceConfiguration] {
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        try await ensureCurrentDeviceLocked(initialEnabled: initialEnabled)
        guard let device = try await store.recordingDevices().first(where: { $0.id == deviceID })
        else { return try await configurationsLocked(includeArchived: false) }

        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let renamed = device.renamed(trimmed.isEmpty ? nil : trimmed)
        guard renamed != device else {
            return try await configurationsLocked(includeArchived: false)
        }
        try await store.perform {
            try await store.setRecordingDevice(renamed)
        }
        return try await configurationsLocked(includeArchived: false)
    }

    /// Hide a non-current stale device and append an off cutoff atomically.
    /// Policy history and raw samples remain available to backups.
    public func archive(
        _ deviceID: RecordingDeviceID,
        initialEnabled: Bool,
    ) async throws -> [RecordingDeviceConfiguration] {
        precondition(deviceID != currentDevice.id, "The current device cannot archive itself.")
        await beginExclusive()
        defer { endExclusive() }
        try requireActive()
        try await ensureCurrentDeviceLocked(initialEnabled: initialEnabled)
        guard let device = try await store.recordingDevices().first(where: { $0.id == deviceID })
        else { return try await configurationsLocked(includeArchived: false) }

        let date = now()
        let changes = try await store.recordingPolicyChanges()
        let change = RecordingPolicyChange(
            id: UUID(),
            deviceID: deviceID,
            effectiveAt: Self.nextEffectiveDate(
                proposed: date,
                after: Self.latestPolicy(for: deviceID, in: changes),
            ),
            isEnabled: false,
        )
        try await store.perform {
            try await store.addRecordingPolicyChange(change)
            try await store.setRecordingDevice(device.archived(at: date))
        }
        return try await configurationsLocked(includeArchived: false)
    }

    /// Permanently close this stack's policy/write gate and quiesce GPS before
    /// reset wipes the store. A queued observer reconciliation resumes behind
    /// this gate, sees the closed state, and cannot recreate the just-erased
    /// current-device rows.
    func quiesce() async {
        await beginExclusive()
        defer { endExclusive() }
        acceptsOperations = false
        await ingestor.quiesce()
    }

    /// A failed reset retains the session, so reopen its operation gate. The
    /// next lifecycle reconciliation decides whether GPS should resume.
    func resumeAfterFailedReset() async {
        await beginExclusive()
        defer { endExclusive() }
        acceptsOperations = true
    }

    private func reconcileLocked(
        initialEnabled: Bool,
        authorization: LocationAuthorizationStatus,
    ) async throws -> RecordingDeviceConfiguration {
        try await ensureCurrentDeviceLocked(initialEnabled: initialEnabled)
        let policies = try await store.recordingPolicyChanges()
        guard let latest = Self.latestPolicy(for: currentDevice.id, in: policies) else {
            preconditionFailure(
                "Current recording device was registered without an initial policy.",
            )
        }

        let status: RecordingDeviceStatus
        if latest.isEnabled, authorization.allowsBackgroundTracking {
            await ingestor.start()
            status = .recording
        } else {
            await ingestor.stop()
            status = latest.isEnabled ? .permissionRequired : .off
        }

        guard let device = try await store.recordingDevices()
            .first(where: { $0.id == currentDevice.id })
        else {
            preconditionFailure("Current recording device disappeared during reconciliation.")
        }
        let checkIn = now()
        let needsAcknowledgement = device.lastAppliedPolicyChangeID != latest.id
            || device.status != status
        let needsPeriodicCheckIn = checkIn.timeIntervalSince(device.lastSeenAt) >= 15 * 60
        let acknowledged = if needsAcknowledgement || needsPeriodicCheckIn {
            device.acknowledging(
                policyChangeID: latest.id,
                status: status,
                at: checkIn,
            )
        } else {
            device
        }
        if acknowledged != device {
            try await store.perform {
                try await store.setRecordingDevice(acknowledged)
            }
        }
        return RecordingDeviceConfiguration(
            device: acknowledged,
            isEnabled: latest.isEnabled,
            latestPolicyChangeID: latest.id,
        )
    }

    private func ensureCurrentDeviceLocked(initialEnabled: Bool) async throws {
        let devices = try await store.recordingDevices()
        let policies = try await store.recordingPolicyChanges()
        let existing = devices.first(where: { $0.id == currentDevice.id })
        let latest = Self.latestPolicy(for: currentDevice.id, in: policies)
        guard existing == nil || latest == nil else { return }

        let date = now()
        let profile = existing ?? RecordingDevice(
            id: currentDevice.id,
            systemName: currentDevice.systemName,
            nickname: nil,
            kind: currentDevice.kind,
            registeredAt: date,
            lastSeenAt: date,
            archivedAt: nil,
            lastAppliedPolicyChangeID: nil,
            status: .off,
        )
        let initialChange = latest ?? RecordingPolicyChange(
            id: UUID(),
            deviceID: currentDevice.id,
            effectiveAt: date,
            isEnabled: initialEnabled,
        )
        try await store.perform {
            if existing == nil {
                try await store.setRecordingDevice(profile)
            }
            if latest == nil {
                try await store.addRecordingPolicyChange(initialChange)
            }
        }
    }

    private func configurationsLocked(
        includeArchived: Bool,
    ) async throws -> [RecordingDeviceConfiguration] {
        async let devices = store.recordingDevices()
        async let policies = store.recordingPolicyChanges()
        let (resolvedDevices, resolvedPolicies) = try await (devices, policies)
        return resolvedDevices
            .filter {
                includeArchived || $0.archivedAt == nil || $0.id == currentDevice.id
            }
            .map { device in
                let latest = Self.latestPolicy(for: device.id, in: resolvedPolicies)
                return RecordingDeviceConfiguration(
                    device: device,
                    isEnabled: latest?.isEnabled ?? true,
                    latestPolicyChangeID: latest?.id,
                )
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

    private static func latestPolicy(
        for deviceID: RecordingDeviceID,
        in changes: [RecordingPolicyChange],
    ) -> RecordingPolicyChange? {
        changes
            .filter { $0.deviceID == deviceID }
            .max { RecordingPolicyChange.isOrderedBefore($0, $1) }
    }

    /// Preserve the local order of rapid actions even when the injected clock
    /// returns the same instant for both. UUID ordering remains the convergent
    /// tie-break for genuinely concurrent changes written on different devices.
    private static func nextEffectiveDate(
        proposed: Date,
        after latest: RecordingPolicyChange?,
    ) -> Date {
        guard let latest, proposed <= latest.effectiveAt else { return proposed }
        return latest.effectiveAt.addingTimeInterval(0.000_001)
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
