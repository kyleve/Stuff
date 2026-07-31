/// Whether this process may contribute automatic locations from the local
/// installation, plus the policy a genuinely new installation starts with.
///
/// A management-only process can still read and edit synced recording-device
/// rows, but it has no local device identity and must never start GPS.
public enum RecordingParticipation: Sendable, Hashable {
    case recording(
        device: CurrentRecordingDevice,
        defaultEnabledForNewInstallation: Bool,
    )
    case managementOnly

    public var currentDevice: CurrentRecordingDevice? {
        switch self {
            case let .recording(device, _): device
            case .managementOnly: nil
        }
    }

    public var defaultEnabledForNewInstallation: Bool {
        switch self {
            case let .recording(_, isEnabled): isEnabled
            case .managementOnly: false
        }
    }

    public var supportsLocalRecording: Bool {
        currentDevice != nil
    }
}
