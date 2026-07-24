import Foundation
import PortholeCore
import PortholeKit
import SwiftData
import SwiftDataInspector

/// A Porthole connector that exposes a SwiftData store, read-only, using
/// SwiftDataInspector's headless reader. Register one per `ModelContainer`; the
/// `id` is explicit (no default) since an app may register several.
public final class SwiftDataConnector: PortholeConnector {
    public let descriptor: PortholeConnectorDescriptor
    private let reader: SwiftDataInspectorReader
    private let rowLimit: Int

    public init(
        id: PortholeConnectorID,
        title: String,
        container: ModelContainer,
        modelTypes: [any PersistentModel.Type]?,
        rowLimit: Int,
    ) {
        descriptor = PortholeConnectorDescriptor(
            id: id,
            title: title,
            summary: "Browse the app's SwiftData store — entities and their rows, read-only.",
            version: 1,
        )
        self.rowLimit = rowLimit
        reader = SwiftDataInspectorReader(
            container: container,
            modelTypes: modelTypes,
            rowLimit: rowLimit,
            valueFormatter: nil,
        )
    }

    public func dataSources() -> [PortholeDataSource] {
        let reader = reader
        let rowLimit = rowLimit
        return [
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "entities",
                    title: "Entities",
                    summary: "One row per SwiftData entity, with its row count and columns.",
                    rowSchema: .object([
                        "name": .string(),
                        "count": .integer(),
                        "columns": .array(of: .string()),
                    ]),
                    filters: .object([:]),
                    supportsSubscription: false,
                ),
                fetch: { _ in
                    let entities = await reader.loadEntities()
                    let rows = entities.map { entity in
                        PortholeValue.object([
                            "name": .string(entity.name),
                            "count": .int(Int64(entity.count)),
                            "columns": .array(entity.columns.map(PortholeValue.string)),
                        ])
                    }
                    return PortholePage(rows: rows, totalCount: rows.count)
                },
            ),
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "rows",
                    title: "Rows",
                    summary: "A page of rows for an entity. Follow nextCursor for more.",
                    rowSchema: .object([:]),
                    filters: .object([
                        "entity": .string("The entity name (from the entities source)"),
                    ], required: ["entity"]),
                    supportsSubscription: false,
                ),
                fetch: { query in
                    guard let name = query.filters["entity"]?.stringValue else {
                        throw PortholeError.invalidParameters("`entity` is required")
                    }
                    let page = Int(query.cursor ?? "1") ?? 1
                    guard let entity = await reader.loadEntities()
                        .first(where: { $0.name == name })
                    else {
                        throw PortholeError.invalidParameters("Unknown entity `\(name)`")
                    }
                    let set = await reader.rows(for: entity, pageCount: max(1, page))
                    // The reader returns a growing prefix; slice this page's window
                    // so pages are disjoint.
                    let start = (max(1, page) - 1) * rowLimit
                    let windowed = start < set.rows.count ? Array(set.rows[start...]) : []
                    let rows = windowed.map { row in
                        PortholeValue.object(row.cells.mapValues(PortholeValue.string))
                    }
                    return PortholePage(
                        rows: rows,
                        nextCursor: set.isTruncated ? String(max(1, page) + 1) : nil,
                        totalCount: set.totalCount,
                    )
                },
            ),
        ]
    }
}
