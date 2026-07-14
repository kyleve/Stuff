import LogKit

/// Logging facade for `RegionKit`. Every logger site routes through
/// ``channel(_:)`` so messages reach both Apple unified logging (Console.app,
/// subsystem `com.stuff.regionkit`) and the shared in-memory ``LogStore`` a
/// log viewer can read (DEBUG builds only).
///
/// RegionKit owns its own subsystem and store rather than borrowing the Where
/// app's `WhereLog`: it's a standalone lower-level module that must not depend
/// on app code. Categories are a typed enum rather than raw strings so a new
/// logger can't silently typo into an untracked category.
public enum RegionLog {
    /// The subsystem every RegionKit log shares.
    public static let subsystem = "com.stuff.regionkit"

    /// Process-wide buffer feeding an in-app log viewer. Logging is inherently
    /// process-global, so a single shared store is the natural home.
    public static let store = LogStore()

    public enum Category: String, CaseIterable, Sendable {
        case attributor = "RegionAttributor"
        case geometryCatalog = "RegionGeometryCatalog"
        case catalog = "RegionCatalog"
    }

    /// A logging channel for `category`, wired to the shared buffer.
    public static func channel(_ category: Category) -> LogChannel {
        LogChannel(subsystem: subsystem, category: category.rawValue, store: store)
    }
}
