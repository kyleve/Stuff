import Foundation

/// An installation's ability to consume the currently observed shared data.
public struct DataCompatibilityStatus: Sendable, Hashable {
    public let supportedVersion: DataCompatibilityVersion
    public let requiredVersion: DataCompatibilityVersion

    public var isCompatible: Bool {
        supportedVersion >= requiredVersion
    }

    public init(
        supportedVersion: DataCompatibilityVersion,
        requiredVersion: DataCompatibilityVersion,
    ) {
        self.supportedVersion = supportedVersion
        self.requiredVersion = requiredVersion
    }

    public func requireAccess() throws {
        guard isCompatible else { throw DataCompatibilityError.updateRequired(self) }
    }
}

/// Typed failures keep compatibility errors distinct from empty data and ordinary launch failures.
public enum DataCompatibilityError: Error, Sendable, Equatable {
    case updateRequired(DataCompatibilityStatus)
    case invalidMetadata
    case metadataTransactionCannotWriteDomainData
    case confirmationRequired(DataCompatibilityActivationReview)
}
