import LogKit
import SwiftUI

/// Host-supplied configuration for ``LogViewer``. Keeps the viewer generic: the
/// host points it at one or more ``LogStore``s and supplies display strings
/// (e.g. a title and a mapping from raw category identifiers to human-readable
/// names).
///
/// Multiple stores let a host surface buffers from several modules (each with
/// its own subsystem/category) in one viewer; entries are merged
/// chronologically. Each `LogEntry` carries its `subsystem`/`category`, so the
/// category filter still tells them apart.
public struct LogViewerConfiguration: Sendable {
    /// The buffers to read and observe, merged chronologically for display.
    public var stores: [LogStore]

    /// Navigation title for the viewer.
    public var title: String

    /// Maps a raw `LogEntry.category` to a display name. Defaults to identity.
    public var categoryDisplayName: @Sendable (String) -> String

    public init(
        stores: [LogStore],
        title: String = "Logs",
        categoryDisplayName: @escaping @Sendable (String) -> String = { $0 },
    ) {
        self.stores = stores
        self.title = title
        self.categoryDisplayName = categoryDisplayName
    }

    /// Convenience for the common single-buffer case.
    public init(
        store: LogStore,
        title: String = "Logs",
        categoryDisplayName: @escaping @Sendable (String) -> String = { $0 },
    ) {
        self.init(stores: [store], title: title, categoryDisplayName: categoryDisplayName)
    }
}
