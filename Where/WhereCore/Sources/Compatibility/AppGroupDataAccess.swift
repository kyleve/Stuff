import Foundation

/// Shared boundary for the app's access evidence and the widget data that evidence authorizes.
/// Resolves the host-injected group lazily so entitlement failures reach the caller's recovery UI.
public nonisolated struct AppGroupDataAccess: DataCompatibilityReceiptStoring,
    DataCompatibilityAccessChecking
{
    private struct Stores {
        let receipts: FileDataCompatibilityReceipt
        let snapshots: WidgetSnapshotStore
    }

    private let stores: @Sendable () throws -> Stores

    public init(appGroupIdentifier: String) {
        stores = {
            guard let directory = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier,
            ) else { throw WidgetSnapshotStore.AppGroupUnavailableError() }
            return Self.makeStores(directory: directory)
        }
    }

    @_spi(Testing)
    public init(directory: URL) {
        stores = { Self.makeStores(directory: directory) }
    }

    private static func makeStores(directory: URL) -> Stores {
        Stores(
            receipts: .inAppGroup(directory: directory),
            snapshots: WidgetSnapshotStore(directory: directory),
        )
    }

    public func load() throws -> DataCompatibilityReceipt? {
        try stores().receipts.load()
    }

    public func save(_ receipt: DataCompatibilityReceipt) throws {
        try stores().receipts.save(receipt)
    }

    public func requireAccess(version: DataModelVersion) throws -> DataCompatibilityReceipt {
        try stores().receipts.requireAccess(version: version)
    }

    public func readWidgetSnapshot(version: DataModelVersion) throws -> WidgetSnapshot? {
        let stores = try stores()
        return try CompatibleWidgetSnapshotReader(
            access: stores.receipts,
            snapshots: stores.snapshots,
        )
        .read(version: version)
    }

    /// The app's publisher supplies its captured origin, never the current receipt's origin.
    public func writeWidgetSnapshot(
        _ snapshot: WidgetSnapshot,
        version: DataModelVersion,
        domain: DataCompatibilityDomain,
    ) throws {
        let stores = try stores()
        let receipt = try stores.receipts.requireAccess(version: version)
        guard receipt.domain == domain else { throw DataCompatibilityTransportError.accountChanged }
        try stores.snapshots.write(.init(snapshot: snapshot, version: version, domain: domain))
    }
}

/// Two receipt reads reject observable changes while the independent snapshot file is loaded.
/// A timeline already delivered to WidgetKit remains subject to the system's reload scheduling.
struct CompatibleWidgetSnapshotReader {
    let access: any DataCompatibilityAccessChecking
    let snapshots: WidgetSnapshotStore

    func read(version: DataModelVersion) throws -> WidgetSnapshot? {
        let before = try access.requireAccess(version: version)
        let persisted = snapshots.read()
        let after = try access.requireAccess(version: version)
        guard before == after else { throw DataCompatibilityTransportError.accountChanged }
        guard let persisted else { return nil }
        guard persisted.version == version, persisted.domain == before.domain else {
            throw DataCompatibilityTransportError.invalidRecord
        }
        return persisted.snapshot
    }
}
