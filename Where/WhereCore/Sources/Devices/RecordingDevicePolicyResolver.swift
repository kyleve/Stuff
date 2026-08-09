import Foundation

/// One generation-pinned read of the records needed to reconcile recording policy.
struct RecordingDevicePolicySnapshot {
    let generation: WhereDataGeneration
    let profiles: [RecordingDeviceProfile]
    let metadataChanges: [RecordingDeviceMetadataChange]
    let checkIns: [RecordingDeviceCheckIn]
    let removals: [RecordingDeviceRemoval]
    let currentDeviceResetBarrier: Date?
}

/// Reads and assembles recording policy inputs while the controller owns physical transitions.
struct RecordingDevicePolicyResolver {
    let store: any WhereStore
    let currentDeviceID: RecordingDeviceID

    func snapshot() async throws -> RecordingDevicePolicySnapshot {
        try await store.readSnapshot {
            async let generation = store.dataGeneration()
            async let profiles = store.recordingDeviceProfiles()
            async let metadataChanges = store.recordingDeviceMetadataChanges()
            async let checkIns = store.recordingDeviceCheckIns()
            async let removals = store.recordingDeviceRemovals()
            let values = try await (generation, profiles, metadataChanges, checkIns, removals)
            let currentProfile = values.1.first { $0.id == currentDeviceID }
            let resetBarrier: Date? = if let currentProfile {
                try await store.recordingDeviceResetBarrier(
                    for: currentProfile.registrationGenerationID,
                )
            } else {
                nil
            }
            return RecordingDevicePolicySnapshot(
                generation: values.0,
                profiles: values.1,
                metadataChanges: values.2,
                checkIns: values.3,
                removals: values.4,
                currentDeviceResetBarrier: resetBarrier,
            )
        }
    }

    func configurations(
        localAutomaticRecordingEnabled: Bool,
        includeRemoved: Bool,
    ) async throws -> [RecordingDeviceConfiguration] {
        try await Self.configurations(
            devices: store.recordingDevices(),
            currentDeviceID: currentDeviceID,
            localAutomaticRecordingEnabled: localAutomaticRecordingEnabled,
            includeRemoved: includeRemoved,
        )
    }

    static func latestMetadata(
        for deviceID: RecordingDeviceID,
        field: RecordingDeviceMetadataField,
        in changes: [RecordingDeviceMetadataChange],
    ) -> RecordingDeviceMetadataChange? {
        changes
            .filter { $0.deviceID == deviceID && $0.field == field }
            .max(by: RecordingDeviceMetadataChange.isOrderedBefore)
    }

    static func nextRevision(
        after revision: Int64?,
        for deviceID: RecordingDeviceID,
    ) throws -> Int64 {
        guard let revision else { return 0 }
        let (next, overflow) = revision.addingReportingOverflow(1)
        guard !overflow else { throw RecordingPersistenceError.revisionExhausted(deviceID) }
        return next
    }

    private static func configurations(
        devices: [RecordingDevice],
        currentDeviceID: RecordingDeviceID,
        localAutomaticRecordingEnabled: Bool,
        includeRemoved: Bool,
    ) -> [RecordingDeviceConfiguration] {
        devices
            .filter { includeRemoved || $0.removedAt == nil || $0.id == currentDeviceID }
            .map { device in
                let isCurrent = device.id == currentDeviceID
                return RecordingDeviceConfiguration(
                    device: device,
                    isCurrentDevice: isCurrent,
                    localAutomaticRecordingEnabled: isCurrent
                        ? localAutomaticRecordingEnabled
                        : nil,
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
}
