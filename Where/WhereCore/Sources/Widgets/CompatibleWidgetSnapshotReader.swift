import Foundation

/// Reads only snapshots whose independent compatibility publication permits this build.
public struct CompatibleWidgetSnapshotReader: Sendable {
    private let snapshotStore: WidgetSnapshotStore
    private let compatibilityStore: WidgetCompatibilityStore

    public init(snapshotStore: WidgetSnapshotStore, compatibilityStore: WidgetCompatibilityStore) {
        self.snapshotStore = snapshotStore
        self.compatibilityStore = compatibilityStore
    }

    public func read() throws -> WidgetSnapshot? {
        guard let publication = try compatibilityStore.read(),
              publication.allowsData else { return nil }
        let snapshot = snapshotStore.read()
        guard try compatibilityStore.read() == publication else { return nil }
        return snapshot
    }
}
