import Foundation
import Observation
import SwiftData

/// The main-actor, observable façade for `SwiftDataInspectorView`. It holds the
/// published entity list and delegates all store work to `SwiftDataInspectorReader`,
/// a background actor — so fetches, reflection, and formatting stay off the main
/// thread and only `Sendable` snapshots come back to the UI.
@MainActor
@Observable
final class SwiftDataInspectorModel {
    let configuration: SwiftDataInspectorConfiguration

    /// The store's entities, populated by `loadEntities()`. Empty until then.
    private(set) var entities: [InspectorEntity] = []

    private let reader: SwiftDataInspectorReader

    init(configuration: SwiftDataInspectorConfiguration) {
        self.configuration = configuration
        reader = SwiftDataInspectorReader(
            container: configuration.container,
            modelTypes: configuration.modelTypes,
            rowLimit: configuration.rowLimit,
            valueFormatter: configuration.valueFormatter,
        )
    }

    var title: String {
        configuration.title
    }

    /// Recompute `entities` from the store (names, counts, and column headers) off
    /// the main thread. Re-invoking picks up rows written since the inspector
    /// opened, since each read uses a fresh context.
    func loadEntities() async {
        entities = await reader.loadEntities()
    }

    /// Load up to `rowLimit` rows for `entity`, formatted for display, off the
    /// main thread.
    func rows(for entity: InspectorEntity) async -> InspectorRowSet {
        await reader.rows(for: entity)
    }
}
