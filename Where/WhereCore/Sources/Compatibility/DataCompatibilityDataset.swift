import Foundation

/// The dataset's sharing contract is independent of a process's local storage adapter.
public enum DataCompatibilityDataset: Hashable, Sendable {
    public struct StoreID: RawRepresentable, Hashable, Codable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            precondition(!rawValue.isEmpty)
            self.rawValue = rawValue
        }
    }

    case local(StoreID)
    case cloudKit(StoreID, containerIdentifier: String)

    public var storeID: StoreID {
        switch self {
            case let .local(storeID), let .cloudKit(storeID, _): storeID
        }
    }
}

/// CloudKit's container-specific user record identity, never a device identity or a display name.
public struct DataCompatibilityAccountID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty)
        self.rawValue = rawValue
    }
}
