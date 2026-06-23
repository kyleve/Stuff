import Foundation
import Observation
import SwiftData

/// The read-only engine behind `SwiftDataInspectorView`: enumerates the store's
/// entities (with live counts and column headers) and loads a page of rows for a
/// chosen entity. Each read uses a fresh throwaway `ModelContext`, so the data
/// reflects the latest committed store state on every refresh and nothing here
/// ever mutates the store.
@MainActor
@Observable
final class SwiftDataInspectorModel {
    let configuration: SwiftDataInspectorConfiguration

    /// The store's entities, populated by `loadEntities()`. Empty until then.
    private(set) var entities: [InspectorEntity] = []

    init(configuration: SwiftDataInspectorConfiguration) {
        self.configuration = configuration
    }

    var title: String {
        configuration.title
    }

    /// Recompute `entities` from the store (names, counts, and column headers).
    /// A fresh `ModelContext` is used each call, so re-invoking it picks up
    /// rows written since the inspector opened.
    func loadEntities() {
        let context = ModelContext(configuration.container)
        let entitiesByName = Dictionary(
            configuration.container.schema.entities.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first },
        )

        let summaries: [InspectorEntity] = if let types = configuration.modelTypes {
            types.map { type in
                makeEntity(
                    type: type,
                    schemaEntity: entitiesByName[String(describing: type)],
                    context: context,
                )
            }
        } else {
            configuration.container.schema.entities.compactMap { schemaEntity in
                guard let type = SwiftDataReflection.metatype(of: schemaEntity) else { return nil }
                return makeEntity(type: type, schemaEntity: schemaEntity, context: context)
            }
        }

        entities = summaries.sorted { $0.name < $1.name }
    }

    /// Load up to `rowLimit` rows for `entity`, formatted for display, against a
    /// fresh context so the page reflects the current store.
    func rows(for entity: InspectorEntity) -> InspectorRowSet {
        let context = ModelContext(configuration.container)
        let models = context.inspectorFetch(entity.type, limit: configuration.rowLimit)
        let total = context.inspectorCount(of: entity.type)
        let rows = models.enumerated().map { index, model in
            InspectorRow(id: index, cells: cells(for: model, entity: entity))
        }
        return InspectorRowSet(rows: rows, totalCount: total, isTruncated: rows.count < total)
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
        if let custom = configuration.valueFormatter?(value) {
            return custom
        }
        if isBinary {
            return Self.binaryDescription(value)
        }
        return Self.defaultFormat(value)
    }

    /// Ordered column names for an entity: attributes first (as declared), then
    /// relationships.
    static func columns(of entity: Schema.Entity) -> [String] {
        entity.attributes.map(\.name) + entity.relationships.map(\.name)
    }

    /// Names of `Data` / `Data?` attributes — these may be external-storage
    /// blobs, so the inspector renders them by size/placeholder rather than
    /// dumping (and potentially faulting in) their bytes.
    static func binaryColumns(of entity: Schema.Entity) -> Set<String> {
        Set(entity.attributes.filter { isBinary($0.valueType) }.map(\.name))
    }

    /// Names of the entity's relationship properties.
    static func relationshipColumns(of entity: Schema.Entity) -> Set<String> {
        Set(entity.relationships.map(\.name))
    }

    private static func isBinary(_ type: Any.Type) -> Bool {
        type == Data.self || type == Data?.self
    }

    /// Display text for a binary column: the byte count when the value is already
    /// an in-memory `Data` (inline storage), otherwise a bare "Data" so an
    /// external-storage future is never resolved just to render the table.
    static func binaryDescription(_ value: Any) -> String {
        if let data = unwrap(value) as? Data {
            return "\(data.count) bytes"
        }
        return "Data"
    }

    /// Built-in display formatting for a stored value, unwrapping optionals so an
    /// `Optional(UUID)` reads as the UUID rather than "Optional(...)".
    static func defaultFormat(_ value: Any) -> String {
        guard let unwrapped = unwrap(value) else { return "nil" }
        switch unwrapped {
            case let string as String: return string
            case let date as Date: return dateFormatter.string(from: date)
            case let data as Data: return "\(data.count) bytes"
            case let uuid as UUID: return uuid.uuidString
            case let bool as Bool: return bool ? "true" : "false"
            default: return String(describing: unwrapped)
        }
    }

    /// Strip any nesting of `Optional` from a reflected value, yielding the inner
    /// value or `nil` when it bottoms out at `.none`.
    private static func unwrap(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        guard let child = mirror.children.first else { return nil }
        return unwrap(child.value)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
