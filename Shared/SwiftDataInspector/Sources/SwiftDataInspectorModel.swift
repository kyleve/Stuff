import Foundation
import Observation
import SwiftData

/// The read-only engine behind `SwiftDataInspectorView`: enumerates the store's
/// entities (with live counts and column headers) and loads a page of rows for a
/// chosen entity. All reads go through one throwaway `ModelContext`, so nothing
/// here ever mutates the store.
@MainActor
@Observable
final class SwiftDataInspectorModel {
    let configuration: SwiftDataInspectorConfiguration

    /// The store's entities, populated by `loadEntities()`. Empty until then.
    private(set) var entities: [InspectorEntity] = []

    private let context: ModelContext

    init(configuration: SwiftDataInspectorConfiguration) {
        self.configuration = configuration
        context = ModelContext(configuration.container)
    }

    var title: String {
        configuration.title
    }

    /// Recompute `entities` from the store (names, counts, and column headers).
    /// Counts are read fresh each call, so re-invoking it refreshes the list.
    func loadEntities() {
        let entitiesByName = Dictionary(
            configuration.container.schema.entities.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first },
        )

        let summaries: [InspectorEntity] = if let types = configuration.modelTypes {
            types.map { type in
                makeEntity(type: type, schemaEntity: entitiesByName[String(describing: type)])
            }
        } else {
            configuration.container.schema.entities.compactMap { schemaEntity in
                guard let type = SwiftDataReflection.metatype(of: schemaEntity) else { return nil }
                return makeEntity(type: type, schemaEntity: schemaEntity)
            }
        }

        entities = summaries.sorted { $0.name < $1.name }
    }

    /// Load up to `rowLimit` rows for `entity`, formatted for display.
    func rows(for entity: InspectorEntity) -> InspectorRowSet {
        let models = context.inspectorFetch(entity.type, limit: configuration.rowLimit)
        let total = context.inspectorCount(of: entity.type)
        let rows = models.enumerated().map { index, model in
            InspectorRow(id: index, cells: cells(for: model, columns: entity.columns))
        }
        return InspectorRowSet(rows: rows, totalCount: total, isTruncated: rows.count < total)
    }

    private func makeEntity(
        type: any PersistentModel.Type,
        schemaEntity: Schema.Entity?,
    ) -> InspectorEntity {
        InspectorEntity(
            name: schemaEntity?.name ?? String(describing: type),
            type: type,
            count: context.inspectorCount(of: type),
            columns: schemaEntity.map(Self.columns(of:)) ?? [],
        )
    }

    private func cells(for model: any PersistentModel, columns: [String]) -> [String: String] {
        let values = SwiftDataReflection.storedValues(of: model)
        var cells: [String: String] = [:]
        for column in columns {
            if let value = values[column] {
                cells[column] = format(value)
            }
        }
        return cells
    }

    private func format(_ value: Any) -> String {
        if let custom = configuration.valueFormatter?(value) {
            return custom
        }
        return Self.defaultFormat(value)
    }

    /// Ordered column names for an entity: attributes first (as declared), then
    /// relationships.
    static func columns(of entity: Schema.Entity) -> [String] {
        entity.attributes.map(\.name) + entity.relationships.map(\.name)
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
