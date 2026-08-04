import Foundation

/// Honest failures from the append-only recording persistence boundary.
public enum RecordingPersistenceError: Error, LocalizedError, Sendable, Hashable {
    case incompleteRemovalHistory
    case conflictingImmutableRecord(id: UUID)
    case deviceNotFound(RecordingDeviceID)
    case currentDeviceNotRegistered(RecordingDeviceID)
    case currentDeviceRemoved(RecordingDeviceID)
    case revisionExhausted(RecordingDeviceID)
    case incompleteDataEpochHistory
    case dataEpochRevisionExhausted
    case dataEpochChanged
    case recordingRewriteInProgress

    public var errorDescription: String? {
        switch self {
            case .incompleteRemovalHistory:
                String(localized: .recordingErrorIncompletePolicyHistory)
            case .conflictingImmutableRecord:
                String(localized: .recordingErrorConflictingImmutableRecord)
            case .deviceNotFound:
                String(localized: .recordingErrorDeviceNotFound)
            case .currentDeviceNotRegistered:
                String(localized: .recordingErrorCurrentDeviceNotRegistered)
            case .currentDeviceRemoved:
                String(localized: .recordingErrorCurrentDevicePolicyUnknown)
            case .revisionExhausted:
                String(localized: .recordingErrorRevisionExhausted)
            case .incompleteDataEpochHistory:
                String(localized: .recordingErrorIncompleteDataEpochHistory)
            case .dataEpochRevisionExhausted:
                String(localized: .recordingErrorDataEpochRevisionExhausted)
            case .dataEpochChanged:
                String(localized: .recordingErrorDataEpochChanged)
            case .recordingRewriteInProgress:
                String(localized: .recordingErrorRewriteInProgress)
        }
    }
}
