import Foundation

/// One server observation. The opaque revision is used for a conditional version increase.
public struct SharedDataModelVersion: Sendable, Equatable {
    public let version: DataModelVersion
    public let revision: String

    public init(version: DataModelVersion, revision: String) {
        self.version = version
        self.revision = revision
    }
}

public enum DataCompatibilityTransportError: Error {
    case unavailable(any Error)
    case conflict
    case invalidRecord
    case accountChanged
}

/// Control-plane I/O, independent of SwiftData and the services protected by the gate.
public protocol DataCompatibilityTransport: Sendable {
    func accountID() async throws -> DataCompatibilityAccountID
    func read(accountID: DataCompatibilityAccountID) async throws -> SharedDataModelVersion?
    func advance(
        accountID: DataCompatibilityAccountID,
        from previous: SharedDataModelVersion?,
        to version: DataModelVersion,
    ) async throws -> SharedDataModelVersion
    func accountChanges() -> AsyncStream<Void>
}

public enum DataCompatibilityFailure: Error, LocalizedError {
    case updateRequired(DataModelVersion)
    case recordingDeviceRequired
    case locationPermissionRequired
    case verificationRequired(any Error)

    public var errorDescription: String? {
        switch self {
            case .updateRequired: String(localized: .compatibilityErrorUpdate)
            case .recordingDeviceRequired: String(localized: .compatibilityErrorRecording)
            case .locationPermissionRequired: String(localized: .compatibilityErrorPermission)
            case .verificationRequired: String(localized: .compatibilityErrorVerify)
        }
    }
}
