import Foundation

public enum DataCompatibilityTransportError: Error {
    case unavailable(any Error)
    case conflict
    case invalidRecord
    case accountChanged
}

/// Control-plane I/O, independent of SwiftData and the services protected by the gate.
public protocol DataCompatibilityTransport: Sendable {
    func domain() async throws -> DataCompatibilityDomain
    func read(domain: DataCompatibilityDomain) async throws -> PersistedDataModelVersion?
    func advance(
        domain: DataCompatibilityDomain,
        from previous: PersistedDataModelVersion?,
        to version: DataModelVersion,
    ) async throws -> PersistedDataModelVersion
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
