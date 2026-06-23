import LogKit
import SwiftUI

/// Host-supplied configuration for ``LogViewer``. Keeps the viewer generic: the
/// host points it at a ``LogStore`` and supplies display strings (e.g. a title
/// and a mapping from raw category identifiers to human-readable names).
public struct LogViewerConfiguration: Sendable {
    /// The buffer to read and observe.
    public var store: LogStore

    /// Navigation title for the viewer.
    public var title: String

    /// Maps a raw `LogEntry.category` to a display name. Defaults to identity.
    public var categoryDisplayName: @Sendable (String) -> String

    public init(
        store: LogStore,
        title: String = "Logs",
        categoryDisplayName: @escaping @Sendable (String) -> String = { $0 },
    ) {
        self.store = store
        self.title = title
        self.categoryDisplayName = categoryDisplayName
    }
}
