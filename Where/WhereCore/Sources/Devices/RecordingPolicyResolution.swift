/// Eventual-consistency state of a device's desired policy.
public enum RecordingPolicyResolution: Sendable, Hashable {
    /// The profile has synced but no policy command has arrived yet.
    case unknown
    case resolved(ResolvedRecordingPolicy)
}
