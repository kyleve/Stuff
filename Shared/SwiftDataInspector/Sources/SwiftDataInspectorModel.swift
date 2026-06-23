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

    /// Load one page of up to `rowLimit` rows for `entity` starting at `offset`,
    /// formatted for display, off the main thread. The detail table requests
    /// `offset: 0` first, then later pages (`offset` = rows already shown) when
    /// the user taps "load more".
    func rows(for entity: InspectorEntity, offset: Int = 0) async -> InspectorRowSet {
        await reader.rows(for: entity, offset: offset)
    }

    /// Resolve a row's relationship into its related rows off the main thread,
    /// for the detail drill-in. This is the only call that faults a relationship,
    /// and only because the user tapped into it.
    func relatedRows(
        of rowID: PersistentIdentifier,
        relationship name: String,
        sourceType: any PersistentModel.Type,
    ) async -> InspectorRelatedRows {
        await reader.relatedRows(of: rowID, relationship: name, sourceType: sourceType)
    }
}
