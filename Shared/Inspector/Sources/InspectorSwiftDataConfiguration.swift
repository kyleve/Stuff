import Foundation
import SwiftData

/// Everything ``InspectorSwiftDataView`` needs to inspect and mutate one
/// SwiftData store.
public struct InspectorSwiftDataConfiguration {
    public let container: ModelContainer

    /// Which model types appear in the root entity list.
    ///
    /// - `nil` (the default): derive every type from `container.schema` via
    ///   reflection — use this for a generic inspector over the whole store.
    /// - `[]`: list nothing (the root shows the empty state even when the store
    ///   has data). This is rarely what you want; prefer `nil` unless you are
    ///   deliberately hiding entities.
    /// - a non-empty array: list only those types, in the order given.
    public let modelTypes: [any PersistentModel.Type]?

    /// Navigation title for the root entity list.
    public let title: String

    /// The page size for fetching rows, so a huge table can't stall the UI: the
    /// table loads one page at a time ("load more" grows the window) and drilling
    /// into a relationship materializes at most this many related rows. The detail
    /// screens note when results are truncated.
    ///
    /// Defaults to `500`. Pass `nil` only when you know the table is small —
    /// `nil` disables pagination and fetches **every** row in one query, which can
    /// stall the UI on large stores.
    public let rowLimit: Int?

    /// Optional override for turning a raw stored value into display text. Return
    /// `nil` to fall back to the inspector's built-in formatting.
    ///
    /// `@Sendable` because formatting runs on the background reader actor; keep
    /// it pure (don't capture main-actor state).
    public let valueFormatter: (@Sendable (Any) -> String?)?
    let makeContainer: @Sendable () throws -> ModelContainer

    public init(
        container: ModelContainer,
        modelTypes: [any PersistentModel.Type]? = nil,
        title: String = "SwiftData",
        rowLimit: Int? = 500,
        valueFormatter: (@Sendable (Any) -> String?)? = nil,
        makeContainer: (@Sendable () throws -> ModelContainer)? = nil,
    ) {
        self.container = container
        self.modelTypes = modelTypes
        self.title = title
        self.rowLimit = rowLimit
        self.valueFormatter = valueFormatter
        self.makeContainer = makeContainer ?? { container }
    }
}

extension InspectorSwiftDataConfiguration {
    init(source: InspectorConfiguration.SwiftDataSource, container: ModelContainer) {
        self.init(
            container: container,
            modelTypes: source.modelTypes,
            title: source.title,
            rowLimit: source.rowLimit,
            valueFormatter: source.valueFormatter,
            makeContainer: source.makeContainer,
        )
    }
}
