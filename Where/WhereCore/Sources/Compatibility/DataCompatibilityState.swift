import Foundation

/// The boot decision for this build and installation. Only compatible permits a domain scope.
public enum DataCompatibilityState: Sendable, Equatable {
    case checking
    case compatible(DataCompatibilityVersion)
    case recordingChoiceRequired
    case updateRequired(DataCompatibilityVersion)
    case waitingForRecordingDevice(RecordingAuthority.Owner)
    case verificationFailed(String)
}

public enum DataCompatibilityError: Error, LocalizedError, Equatable, Sendable {
    case updateRequired(DataCompatibilityVersion)
    case accessRevoked
    case notReady
    case verificationFailed(String)
}

extension DataCompatibilityError {
    public var errorDescription: String? {
        switch self {
            case let .updateRequired(version): "This data requires compatibility version \(version.rawValue). Update the app to continue."
            case .accessRevoked: "This app session no longer has access to shared data."
            case .notReady: "Shared data compatibility has not been verified."
            case let .verificationFailed(description): "Could not verify shared data compatibility: \(description)"
        }
    }
}
