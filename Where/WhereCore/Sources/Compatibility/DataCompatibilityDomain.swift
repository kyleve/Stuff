import Foundation

/// The authority whose version was checked. A local receipt never proves cloud publication.
public enum DataCompatibilityDomain: Codable, Hashable, Sendable {
    case local
    case cloud(DataCompatibilityAccountID)

    public var usesCloudKit: Bool {
        switch self {
            case .local: false
            case .cloud: true
        }
    }

    var isValid: Bool {
        switch self {
            case .local: true
            case let .cloud(account):
                !account.containerIdentifier.isEmpty && !account.userRecordName.isEmpty
        }
    }
}
