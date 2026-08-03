/// Honest physical state of automatic recording on the current installation.
public enum RecordingDeviceRuntimeState: Sendable, Hashable {
    /// Desired policy, physical monitoring, and durable acknowledgement agree.
    case applied(RecordingDeviceConfiguration)
    /// Core stopped monitoring because it could not prove or persist the applicable policy.
    case unavailable
}

/// One controller-ordered runtime emission. The process-local sequence lets presentation merge
/// direct command results with the async stream without an older suspended caller overwriting a
/// newer CloudKit-driven state.
public struct RecordingDeviceRuntimeUpdate: Sendable, Hashable {
    public let sequence: UInt64
    public let state: RecordingDeviceRuntimeState
}
