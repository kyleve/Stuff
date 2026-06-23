import Foundation
import SwiftData

/// The off-main engine behind the inspector. A plain `actor` runs on the
/// cooperative thread pool, so every fetch, count, `Mirror` reflection, and
/// value-formatting happens off the main thread; only `Sendable` snapshots
/// (`InspectorEntity`, `InspectorRowSet`) cross back to the UI.
///
/// SwiftData's `ModelContext` and `PersistentModel` aren't `Sendable` and must
/// stay on a single actor, so the context is created and used entirely inside
/// here and never escapes. Each call opens a fresh read-only context, so results
/// reflect the latest committed store state and nothing is ever mutated.
actor SwiftDataInspectorReader {
    private let container: ModelContainer
    private let modelTypes: [any PersistentModel.Type]?
    private let rowLimit: Int?
    private let valueFormatter: (@Sendable (Any) -> String?)?

    init(
        container: ModelContainer,
        modelTypes: [any PersistentModel.Type]?,
        rowLimit: Int?,
        valueFormatter: (@Sendable (Any) -> String?)?,
    ) {
        self.container = container
        self.modelTypes = modelTypes
        self.rowLimit = rowLimit
        self.valueFormatter = valueFormatter
    }

    /// Enumerate the store's entities with live counts and column headers, sorted
    /// by name.
    func loadEntities() -> [InspectorEntity] {
        let context = ModelContext(container)
        let entitiesByName = Dictionary(
            container.schema.entities.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first },
        )

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

        return summaries.sorted { $0.name < $1.name }
    }

    /// Fetch up to `rowLimit` rows for `entity`, formatted for display, plus the
    /// per-column character counts the view needs to size columns.
    func rows(for entity: InspectorEntity) -> InspectorRowSet {
        let context = ModelContext(container)
        let models = context.inspectorFetch(entity.type, limit: rowLimit)
        let total = context.inspectorCount(of: entity.type)
        let rows = models.enumerated().map { index, model in
            InspectorRow(id: index, cells: cells(for: model, entity: entity))
        }
        return InspectorRowSet(
            rows: rows,
            totalCount: total,
            isTruncated: rows.count < total,
            columnCharacterCounts: Self.columnCharacterCounts(for: rows, columns: entity.columns),
        )
    }

    private func makeEntity(
        type: any PersistentModel.Type,
        schemaEntity: Schema.Entity?,
        context: ModelContext,
    ) -> InspectorEntity {
        InspectorEntity(
            name: schemaEntity?.name ?? String(describing: type),
            type: type,
            count: context.inspectorCount(of: type),
            columns: schemaEntity.map(Self.columns(of:)) ?? [],
            binaryColumns: schemaEntity.map(Self.binaryColumns(of:)) ?? [],
            relationshipColumns: schemaEntity.map(Self.relationshipColumns(of:)) ?? [],
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
        if let data = unwrap(value) as? Data {
            return "\(data.count) bytes"
        }
        return "Data"
    }

    /// Built-in display formatting for a stored value, unwrapping optionals so an
    /// `Optional(UUID)` reads as the UUID rather than "Optional(...)".
    nonisolated static func defaultFormat(_ value: Any) -> String {
        guard let unwrapped = unwrap(value) else { return "nil" }
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

    /// Strip any nesting of `Optional` from a reflected value, yielding the inner
    /// value or `nil` when it bottoms out at `.none`.
    private nonisolated static func unwrap(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        guard let child = mirror.children.first else { return nil }
        return unwrap(child.value)
    }
}
