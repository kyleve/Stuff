import Foundation
import Observation
import SwiftData

/// The main-actor, observable façade for `InspectorSwiftDataView`. It holds the
/// published entity list and delegates all store work to `InspectorSwiftDataStore`,
/// a background actor — so fetches, reflection, and formatting stay off the main
/// thread and only `Sendable` snapshots come back to the UI.
@MainActor
@Observable
final class InspectorSwiftDataModel {
    /// The store's entities, populated by `loadEntities()`. Empty until then.
    private(set) var entities: [InspectorEntity] = []
    private(set) var operationError: String?
    private(set) var mutationGeneration = 0

    private let displayTitle: String
    private let reader: InspectorSwiftDataStore

    init(configuration: InspectorSwiftDataConfiguration) {
        displayTitle = configuration.title
        reader = InspectorSwiftDataStore(
            container: configuration.container,
            modelTypes: configuration.modelTypes,
            rowLimit: configuration.rowLimit,
            valueFormatter: configuration.valueFormatter,
            makeContainer: configuration.makeContainer,
        )
    }

    init(
        source: InspectorConfiguration.SwiftDataSource,
        store: InspectorSwiftDataStore,
    ) {
        displayTitle = source.title
        reader = store
    }

    var title: String {
        displayTitle
    }

    var isPresentingOperationError: Bool {
        get { operationError != nil }
        set {
            if !newValue {
                operationError = nil
            }
        }
    }

    /// Recompute `entities` from the store (names, counts, and column headers) off
    /// the main thread. Re-invoking picks up rows written since the inspector
    /// opened, since each read uses a fresh context.
    func loadEntities() async {
        do {
            entities = try await reader.loadEntities()
            operationError = nil
        } catch is CancellationError {
            return
        } catch {
            report(error)
        }
    }

    /// Load the first `pageCount` pages (each up to `rowLimit` rows) for `entity`,
    /// formatted for display, off the main thread. The detail table requests
    /// `pageCount: 1` first, then a higher count when the user taps "load more" —
    /// each call returns the whole prefix so the table can replace its rows with
    /// a single consistent fetch.
    func rows(
        for entity: InspectorEntity,
        pageCount: Int = 1,
    ) async throws -> InspectorRowSet {
        try await reader.rows(for: entity, pageCount: pageCount)
    }

    /// Resolve a row's relationship into its related rows off the main thread,
    /// for the detail drill-in. This is the only call that faults a relationship,
    /// and only because the user tapped into it.
    func relatedRows(
        of rowID: PersistentIdentifier,
        relationship name: String,
        sourceType: any PersistentModel.Type,
    ) async throws -> InspectorRelatedRows {
        try await reader.relatedRows(of: rowID, relationship: name, sourceType: sourceType)
    }

    func storeURLs() async -> [URL] {
        await reader.storeURLs
    }

    func delete(rowID: PersistentIdentifier, from entity: InspectorEntity) async -> Bool {
        do {
            try await reader.deleteRow(id: rowID, entityType: entity.type)
            operationError = nil
            mutationGeneration += 1
            await loadEntities()
            return true
        } catch is CancellationError {
            return false
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }

    func deleteAllRows(from entity: InspectorEntity) async -> Bool {
        do {
            try await reader.deleteAllRows(of: entity.type)
            operationError = nil
            mutationGeneration += 1
            await loadEntities()
            return true
        } catch is CancellationError {
            return false
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }

    func eraseStore() async -> Bool {
        do {
            _ = try await reader.eraseAndReopen()
            operationError = nil
            mutationGeneration += 1
            await loadEntities()
            return true
        } catch is CancellationError {
            return false
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }

    func report(_ error: any Error) {
        operationError = error.localizedDescription
    }
}
