import Foundation
import SwiftData

/// Everything `SwiftDataInspectorView` needs to browse a store. Build one from
/// any `ModelContainer` and hand it to the view; the inspector is read-only and
/// works for any SwiftData schema.
public struct SwiftDataInspectorConfiguration {
    /// The store to inspect. The inspector only ever reads from it (through a
    /// throwaway `ModelContext`) — it never writes or deletes.
    public let container: ModelContainer

    /// The model types to list. When `nil` (the default) the inspector derives
    /// them from `container.schema` via reflection. Supply them explicitly when
    /// you already hold the types and want to skip the reflection fallback.
    public let modelTypes: [any PersistentModel.Type]?

    /// Navigation title for the root entity list.
    public let title: String

    /// The most rows fetched per entity, so a huge table can't stall the UI; the
    /// detail screen notes when results are truncated. `nil` fetches every row.
    public let rowLimit: Int?

    /// Optional override for turning a raw stored value into display text. Return
    /// `nil` to fall back to the inspector's built-in formatting.
    public let valueFormatter: ((Any) -> String?)?

    public init(
        container: ModelContainer,
        modelTypes: [any PersistentModel.Type]? = nil,
        title: String = "SwiftData",
        rowLimit: Int? = 500,
        valueFormatter: ((Any) -> String?)? = nil,
    ) {
        self.container = container
        self.modelTypes = modelTypes
        self.title = title
        self.rowLimit = rowLimit
        self.valueFormatter = valueFormatter
    }
}
