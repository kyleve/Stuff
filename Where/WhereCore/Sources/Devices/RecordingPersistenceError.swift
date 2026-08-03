import Foundation

/// Honest failures from the append-only recording persistence boundary.
public enum RecordingPersistenceError: Error, LocalizedError, Sendable, Hashable {
    case incompleteAssignmentHistory
    case assignmentRevisionExhausted
    case conflictingImmutableRecord(id: UUID)
    case deviceNotFound(RecordingDeviceID)
    case currentDeviceNotRegistered(RecordingDeviceID)
    case currentDeviceAssignmentUnknown(RecordingDeviceID)
    case revisionExhausted(RecordingDeviceID)
    case incompleteDataEpochHistory
    case dataEpochRevisionExhausted
    case dataEpochChanged
    case recordingRewriteInProgress

    public var errorDescription: String? {
        switch self {
            case .incompleteAssignmentHistory:
                String(localized: .recordingErrorIncompletePolicyHistory)
            case .assignmentRevisionExhausted:
                String(localized: .recordingErrorRevisionExhausted)
            case .conflictingImmutableRecord:
                String(localized: .recordingErrorConflictingImmutableRecord)
            case .deviceNotFound:
                String(localized: .recordingErrorDeviceNotFound)
            case .currentDeviceNotRegistered:
                String(localized: .recordingErrorCurrentDeviceNotRegistered)
            case .currentDeviceAssignmentUnknown:
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
