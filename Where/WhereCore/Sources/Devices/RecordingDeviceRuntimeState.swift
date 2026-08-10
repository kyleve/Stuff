/// Honest physical state of automatic recording on the current installation.
public enum RecordingDeviceRuntimeState: Sendable, Hashable {
    /// Local consent, physical monitoring, and the advisory check-in agree.
    case applied(RecordingDeviceConfiguration)
    /// This installation identity was globally removed and cannot record again.
    case removed
    /// Core stopped monitoring because it could not read or persist the applicable state.
    case unavailable
}

/// One controller-ordered runtime emission. The process-local sequence lets presentation merge
/// direct command results with the async stream without an older suspended caller overwriting a
/// newer CloudKit-driven state.
public struct RecordingDeviceRuntimeUpdate: Sendable, Hashable {
    public let sequence: UInt64
    public let state: RecordingDeviceRuntimeState
}
