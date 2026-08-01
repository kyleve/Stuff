import Foundation
import SwiftData

/// The off-main engine behind the inspector. A plain `actor` runs on the
/// cooperative thread pool, so every fetch, count, `Mirror` reflection, and
/// value-formatting happens off the main thread; only `Sendable` snapshots
/// (`InspectorEntity`, `InspectorRowSet`) cross back to the UI.
///
/// SwiftData's `ModelContext` and `PersistentModel` aren't `Sendable` and must
/// stay on a single actor, so the context is created and used entirely inside
/// here and never escapes. Each call opens a fresh context, so results reflect
/// the latest committed state; reads and confirmed mutations serialize here.
actor InspectorSwiftDataStore {
    private var container: ModelContainer?
    private let modelTypes: [any PersistentModel.Type]?
    private let rowLimit: Int?
    private let valueFormatter: (@Sendable (Any) -> String?)?
    private let makeContainer: (@Sendable () throws -> ModelContainer)?
    private let recoveryStorage: InspectorSwiftDataStoreFamily.RecoveryStorage?
    private let fileManager = FileManager()

    init(
        container: ModelContainer,
        modelTypes: [any PersistentModel.Type]?,
        rowLimit: Int?,
        valueFormatter: (@Sendable (Any) -> String?)?,
        makeContainer: (@Sendable () throws -> ModelContainer)?,
        recoveryStorage: InspectorSwiftDataStoreFamily.RecoveryStorage?,
    ) {
        self.container = container
        self.modelTypes = modelTypes
        self.rowLimit = rowLimit
        self.valueFormatter = valueFormatter
        self.makeContainer = makeContainer
        self.recoveryStorage = recoveryStorage
    }

    init(source: InspectorConfiguration.SwiftDataSource) throws {
        container = try source.makeContainer()
        modelTypes = source.modelTypes
        rowLimit = source.rowLimit
        valueFormatter = source.valueFormatter
        makeContainer = source.makeContainer
        recoveryStorage = InspectorSwiftDataStoreFamily.RecoveryStorage(
            storageRootURL: source.storageRootURL,
            urls: source.recoveryStorageURLs,
        )
    }

    var storeURLs: [URL] {
        container?.configurations.map(\.url) ?? []
    }

    /// Enumerate the store's entities with live counts and column headers, sorted
    /// by name.
    func loadEntities() throws -> [InspectorEntity] {
        try Task.checkCancellation()
        let container = try openContainer()
        let context = ModelContext(container)
        let entitiesByName = Self.entitiesByName(in: container.schema)

        let summaries: [InspectorEntity] = if let modelTypes {
            modelTypes.map { type in
                makeEntity(
                    type: type,
                    schemaEntity: entitiesByName[String(describing: type)],
                    context: context,
                )
            }
        } else {
            container.schema.entities.compactMap { schemaEntity in
                guard let type = SwiftDataReflection.metatype(of: schemaEntity) else { return nil }
                return makeEntity(type: type, schemaEntity: schemaEntity, context: context)
            }
        }

        try Task.checkCancellation()
        return summaries.sorted { $0.name < $1.name }
    }

    /// Fetch the first `pageCount` pages (each up to `rowLimit` rows) for
    /// `entity`, formatted for display, plus the per-column character counts the
    /// view needs to size columns. `pageCount` powers "load more": the table
    /// re-requests with a higher count and replaces its rows with this longer,
    /// single-fetch prefix. `isTruncated` reports whether rows remain beyond it.
    func rows(for entity: InspectorEntity, pageCount: Int = 1) throws -> InspectorRowSet {
        try Task.checkCancellation()
        let container = try openContainer()
        let context = ModelContext(container)
        let limit = rowLimit.map { $0 * max(pageCount, 1) }
        let models = context.inspectorFetch(entity.type, limit: limit)
        let total: Int
        let isTruncated: Bool
        if let limit, models.count < limit {
            // The fetch returned fewer rows than requested — everything is loaded.
            total = models.count
            isTruncated = false
        } else if limit == nil {
            total = models.count
            isTruncated = false
        } else {
            total = context.inspectorCount(of: entity.type)
            isTruncated = models.count < total
        }
        let rows = models.map { model in
            InspectorRow(
                persistentID: model.persistentModelID,
                cells: cells(for: model, entity: entity),
            )
        }
        try Task.checkCancellation()
        return InspectorRowSet(
            rows: rows,
            totalCount: total,
            isTruncated: isTruncated,
            columnCharacterCounts: Self.columnCharacterCounts(for: rows, columns: entity.columns),
        )
    }

    /// Resolve the `relationship` of the row identified by `rowID` (a model of
    /// `sourceType`) into its related rows, off the main thread. Unlike the table
    /// — which never faults a relationship just to draw a row — this is the one
    /// place the inspector reads a relationship, and only because the user
    /// explicitly drilled into it.
    ///
    /// Returns an empty result (no entity, no rows) if the source row is gone or
    /// the relationship is empty/unreadable, so the detail view degrades to an
    /// empty state rather than trapping.
    func relatedRows(
        of rowID: PersistentIdentifier,
        relationship name: String,
        sourceType: any PersistentModel.Type,
    ) throws -> InspectorRelatedRows {
        try Task.checkCancellation()
        let container = try openContainer()
        let context = ModelContext(container)
        guard let source = context.inspectorModel(sourceType, id: rowID) else {
            return InspectorRelatedRows(entity: nil, rows: [], isToMany: false, totalCount: 0)
        }

        let references = SwiftDataReflection.relatedReferences(
            of: source,
            named: name,
            schema: container.schema,
        )
        guard let destinationType = references.destinationType else {
            return InspectorRelatedRows(
                entity: nil,
                rows: [],
                isToMany: references.isToMany,
                totalCount: 0,
            )
        }

        // Cap how many related rows we materialize to the same page size as a
        // table, so drilling into a huge to-many can't fault an unbounded number
        // of rows into memory. The UI surfaces the shortfall via `totalCount`.
        let totalCount = references.ids.count
        let wantedIDs = rowLimit.map { Array(references.ids.prefix($0)) } ?? references.ids

        let entitiesByName = Self.entitiesByName(in: container.schema)
        let entity = Self.makeEntity(
            type: destinationType,
            schemaEntity: entitiesByName[String(describing: destinationType)],
            count: context.inspectorCount(of: destinationType),
        )

        // Materialize the wanted rows in a single fetch (the relationship fault
        // yields rows whose attribute slots are still unresolved), then render
        // them in the relationship's own order with the same placeholder rules.
        let modelsByID = context.inspectorModels(destinationType, ids: wantedIDs)
        let rows = wantedIDs.compactMap { id -> InspectorRow? in
            guard let related = modelsByID[id] else { return nil }
            return InspectorRow(
                persistentID: related.persistentModelID,
                cells: cells(for: related, entity: entity),
            )
        }

        try Task.checkCancellation()
        return InspectorRelatedRows(
            entity: rows.isEmpty ? nil : entity,
            rows: rows,
            isToMany: references.isToMany,
            totalCount: totalCount,
        )
    }

    func deleteRow(
        id: PersistentIdentifier,
        entityType: any PersistentModel.Type,
    ) throws {
        try Task.checkCancellation()
        let context = try ModelContext(openContainer())
        try context.inspectorDelete(entityType, id: id)
    }

    func deleteAllRows(of entityType: any PersistentModel.Type) throws {
        try Task.checkCancellation()
        let context = try ModelContext(openContainer())
        try context.inspectorDeleteAll(entityType)
    }

    /// Erase the complete store using SwiftData's supported API, then replace
    /// this actor's only container reference with a newly opened empty one.
    func eraseAndReopen() throws -> [URL] {
        guard let makeContainer else {
            throw InspectorSwiftDataStoreError.erasureUnavailable
        }
        var erasedContainer: ModelContainer? = try openContainer()
        let reopened = try Self.performEraseAndReopen(
            erase: {
                try erasedContainer?.erase()
                try recoveryStorage?.erase(using: fileManager)
            },
            discard: {
                container = nil
                erasedContainer = nil
            },
            reopen: makeContainer,
        )
        container = reopened
        return reopened.configurations.map(\.url)
    }

    /// Honor cancellation before destructive work, then always finish
    /// discarding and reopening once erasure has begun.
    static func performEraseAndReopen<Reopened>(
        erase: () throws -> Void,
        discard: () -> Void,
        reopen: () throws -> Reopened,
    ) throws -> Reopened {
        try Task.checkCancellation()
        try erase()
        discard()
        return try reopen()
    }

    private func openContainer() throws -> ModelContainer {
        guard let container else {
            throw InspectorSwiftDataStoreError.containerUnavailable
        }
        return container
    }

    /// The schema's entities keyed by name, keeping the first on a duplicate.
    private nonisolated static func entitiesByName(in schema: Schema) -> [String: Schema.Entity] {
        Dictionary(schema.entities.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func makeEntity(
        type: any PersistentModel.Type,
        schemaEntity: Schema.Entity?,
        context: ModelContext,
    ) -> InspectorEntity {
        Self.makeEntity(
            type: type,
            schemaEntity: schemaEntity,
            count: context.inspectorCount(of: type),
        )
    }

    /// Build an entity summary from already-resolved, `Sendable` inputs (the
    /// concrete type, its schema entity, and a precomputed row count). Pure, so
    /// the relationship resolver can call it without threading the non-`Sendable`
    /// `ModelContext` through — keeping the model and the context in separate
    /// isolation regions.
    private nonisolated static func makeEntity(
        type: any PersistentModel.Type,
        schemaEntity: Schema.Entity?,
        count: Int,
    ) -> InspectorEntity {
        InspectorEntity(
            name: schemaEntity?.name ?? String(describing: type),
            type: type,
            count: count,
            columns: schemaEntity.map(columns(of:)) ?? [],
            binaryColumns: schemaEntity.map(binaryColumns(of:)) ?? [],
            relationshipColumns: schemaEntity.map(relationshipColumns(of:)) ?? [],
        )
    }

    private func cells(
        for model: any PersistentModel,
        entity: InspectorEntity,
    ) -> [String: String] {
        let values = SwiftDataReflection.storedValues(of: model)
        var cells: [String: String] = [:]
        for column in entity.columns {
            // Relationships render as a placeholder without reading the slot, so
            // the related object graph is never faulted in for a debug table.
            if entity.relationshipColumns.contains(column) {
                cells[column] = "(relationship)"
                continue
            }
            guard let value = values[column] else { continue }
            cells[column] = format(value, isBinary: entity.binaryColumns.contains(column))
        }
        return cells
    }

    private func format(_ value: Any, isBinary: Bool) -> String {
        if let custom = valueFormatter?(value) {
            return custom
        }
        if isBinary {
            return Self.binaryDescription(value)
        }
        return Self.defaultFormat(value)
    }

    // MARK: - Pure helpers (nonisolated: safe to call from any actor / tests)

    /// Ordered column names for an entity: attributes first (as declared), then
    /// relationships.
    nonisolated static func columns(of entity: Schema.Entity) -> [String] {
        entity.attributes.map(\.name) + entity.relationships.map(\.name)
    }

    /// Names of `Data` / `Data?` attributes — these may be external-storage
    /// blobs, so the inspector renders them by size/placeholder rather than
    /// dumping (and potentially faulting in) their bytes.
    nonisolated static func binaryColumns(of entity: Schema.Entity) -> Set<String> {
        Set(entity.attributes.filter { isBinary($0.valueType) }.map(\.name))
    }

    /// Names of the entity's relationship properties.
    nonisolated static func relationshipColumns(of entity: Schema.Entity) -> Set<String> {
        Set(entity.relationships.map(\.name))
    }

    private nonisolated static func isBinary(_ type: Any.Type) -> Bool {
        type == Data.self || type == Data?.self
    }

    /// Display text for a binary column: the byte count when the value is already
    /// an in-memory `Data` (inline storage), otherwise a bare "Data" so an
    /// external-storage future is never resolved just to render the table.
    nonisolated static func binaryDescription(_ value: Any) -> String {
        if let data = InspectorOptionalUnwrapping.unwrap(value) as? Data {
            return "\(data.count) bytes"
        }
        return "Data"
    }

    /// Built-in display formatting for a stored value, unwrapping optionals so an
    /// `Optional(UUID)` reads as the UUID rather than "Optional(...)".
    nonisolated static func defaultFormat(_ value: Any) -> String {
        guard let unwrapped = InspectorOptionalUnwrapping.unwrap(value) else { return "nil" }
        switch unwrapped {
            case let string as String: return string
            case let date as Date: return date.formatted(date: .numeric, time: .standard)
            case let data as Data: return "\(data.count) bytes"
            case let uuid as UUID: return uuid.uuidString
            case let bool as Bool: return bool ? "true" : "false"
            default: return String(describing: unwrapped)
        }
    }

    /// Longest cell string (in characters) per column, so the view can size
    /// monospaced columns without re-scanning every cell on the main thread.
    nonisolated static func columnCharacterCounts(
        for rows: [InspectorRow],
        columns: [String],
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for column in columns {
            var maxCharacters = 0
            for row in rows {
                if let count = row.cells[column]?.count {
                    maxCharacters = max(maxCharacters, count)
                }
            }
            counts[column] = maxCharacters
        }
        return counts
    }
}

private enum InspectorSwiftDataStoreError: LocalizedError {
    case containerUnavailable
    case erasureUnavailable

    var errorDescription: String? {
        switch self {
            case .containerUnavailable:
                "The SwiftData store is unavailable. Reopen Inspector to try again."
            case .erasureUnavailable:
                "This store cannot be erased because no fresh-container factory was configured."
        }
    }
}
