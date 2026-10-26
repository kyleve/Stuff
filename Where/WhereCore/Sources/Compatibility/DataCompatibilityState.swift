import Foundation

/// The boot decision for this build and installation. Only compatible permits a domain scope.
public enum DataCompatibilityState: Sendable, Equatable {
    case checking
    case compatible(DataCompatibilityVersion)
    case recordingChoiceRequired
    case updateRequired(DataCompatibilityVersion)
    case waitingForRecordingDevice(RecordingAuthority.Owner)
    case verificationFailed(DataCompatibilityFailure)
}

public enum DataCompatibilityError: Error, LocalizedError, Equatable, Sendable {
    case updateRequired(DataCompatibilityVersion)
    case recordingDeviceUpdateRequired
    case recordingChoiceRequired
    case accessRevoked
    case notReady
    case verificationFailed(DataCompatibilityFailure)
}

extension DataCompatibilityError {
    public var errorDescription: String? {
        switch self {
            case let .updateRequired(version): "This data requires compatibility version \(version.rawValue). Update the app to continue."
            case .recordingDeviceUpdateRequired: "Update and open Where on the recording device first."
            case .recordingChoiceRequired: "Open Where and choose whether this device should record."
            case .accessRevoked: "This app session no longer has access to shared data."
            case .notReady: "Shared data compatibility has not been verified."
            case let .verificationFailed(failure): "Could not verify shared data compatibility: \(failure.error.localizedDescription)"
        }
    }
}

extension DataCompatibilityState {
    public var blockingError: DataCompatibilityError? {
        switch self {
            case .checking: .notReady
            case .compatible: nil
            case .recordingChoiceRequired: .recordingChoiceRequired
            case let .updateRequired(version): .updateRequired(version)
            case .waitingForRecordingDevice: .recordingDeviceUpdateRequired
            case let .verificationFailed(failure): .verificationFailed(failure)
        }
    }
}

/// Orders asynchronous presentations from one process-owned coordinator.
public struct DataCompatibilitySnapshot: Sendable, Equatable {
    public let revision: UInt64
    public let state: DataCompatibilityState
}
