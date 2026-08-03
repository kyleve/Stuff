import Foundation

/// One row shown by device-management UI: the assembled profile plus an honest
/// policy resolution that can represent staggered CloudKit delivery.
public struct RecordingDeviceConfiguration: Identifiable, Sendable, Hashable {
    public let device: RecordingDevice
    public let policy: RecordingPolicyResolution

    public var id: RecordingDeviceID {
        device.id
    }

    public var isEnabled: Bool? {
        guard case let .resolved(policy) = policy else { return nil }
        return policy.isEnabled
    }

    public var latestPolicyChangeID: UUID? {
        guard case let .resolved(policy) = policy else { return nil }
        return policy.changeID
    }

    public var isArchived: Bool {
        guard case let .resolved(policy) = policy else { return false }
        return policy.isArchived
    }

    public var isPending: Bool {
        switch policy {
            case .unknown: true
            case let .resolved(policy): policy.isAcknowledged == false
        }
    }

    public init(
        device: RecordingDevice,
        policy: RecordingPolicyResolution,
    ) {
        self.device = device
        self.policy = policy
    }

    /// Convenience for callers assembling a configuration from a known policy.
    public init(device: RecordingDevice, policyChange: RecordingPolicyChange) {
        self.init(
            device: device,
            policyChange: policyChange,
            requiredCleanupToken: nil,
        )
    }

    init(
        device: RecordingDevice,
        policyChange: RecordingPolicyChange,
        requiredCleanupToken: RecordingPolicyCleanupToken?,
    ) {
        let isEffectivelyEnabled = policyChange.isEnabled
        let acknowledgedStatus = if isEffectivelyEnabled {
            device.status == .recording || device.status == .permissionRequired
        } else {
            device.status == .off
        }
        self.init(
            device: device,
            policy: .resolved(ResolvedRecordingPolicy(
                isEnabled: isEffectivelyEnabled,
                isArchived: policyChange.isArchived,
                changeID: policyChange.id,
                isAcknowledged: device.lastAppliedPolicyChangeID == policyChange.id
                    && device.lastDiscardedPolicyFrontierToken == requiredCleanupToken
                    && acknowledgedStatus,
            )),
        )
    }
}
