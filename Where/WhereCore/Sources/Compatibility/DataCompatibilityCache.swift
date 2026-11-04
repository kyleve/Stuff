import Foundation

/// Device-local verification evidence. Absence is distinct from an unreadable cache.
/// Keep this file outside backups: a restore must verify its account/store binding again.
public struct DataCompatibilityCache: Codable, Hashable, Sendable {
    public let storeID: DataCompatibilityDataset.StoreID
    public let accountID: DataCompatibilityAccountID
    public let requiredMajor: UInt
    public let verified: Bool

    public init(
        storeID: DataCompatibilityDataset.StoreID,
        accountID: DataCompatibilityAccountID,
        requiredMajor: UInt,
        verified: Bool,
    ) {
        self.storeID = storeID
        self.accountID = accountID
        self.requiredMajor = requiredMajor
        self.verified = verified
    }
}

@MainActor
public protocol DataCompatibilityCacheStoring: AnyObject {
    func load() throws -> DataCompatibilityCache?
    func save(_ value: DataCompatibilityCache) throws
}

/// In-memory cache for local fixtures; production supplies a backup-excluded durable file.
@MainActor
public final class InMemoryDataCompatibilityCache: DataCompatibilityCacheStoring {
    private var value: DataCompatibilityCache?

    public init(value: DataCompatibilityCache?) {
        self.value = value
    }

    public func load() throws -> DataCompatibilityCache? {
        value
    }

    public func save(_ value: DataCompatibilityCache) throws {
        self.value = value
    }
}
