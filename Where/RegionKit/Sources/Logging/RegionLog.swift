import PeriscopeCore

/// Phantom root event naming RegionKit's log scope tree. It is never emitted —
/// its only job is to give ``RegionLog``'s root `Log` the scope name
/// `"RegionKit"`, so every RegionKit event sits under one filterable subtree.
struct RegionKitRoot: LogEvent {
    static let eventName = "RegionKit"
    var message: String {
        ""
    }
}

/// Logging facade for `RegionKit`. Every logger site derives from one root
/// `Log` scoped `"RegionKit"`, so RegionKit's events form a single subtree
/// under Periscope's process-wide system (``Periscope/shared``) — the log
/// viewer filters or inspects them as a group, and each collaborator's events
/// live in their own named child scope.
///
/// RegionKit owns its own root scope rather than borrowing the Where app's
/// `WhereLog`: it's a standalone lower-level module that must not depend on app
/// code. Loggers are typed to a per-collaborator ``LogEvent`` so a new event
/// can't silently typo into an untracked category.
public enum RegionLog {
    /// The `"RegionKit"` root every RegionKit logger descends from.
    static let root = Log<RegionKitRoot>(system: .shared)

    /// `RegionAttributor` — surfaces missing/unparseable bundled geometry as
    /// faults alongside the debug-build `assertionFailure`.
    static let attributor = root(RegionAttributorLog.self)

    /// `RegionCatalog` — the bundled `regions.json` manifest load.
    static let catalog = root(RegionCatalogLog.self)

    /// `RegionGeometryCatalog` — the developer region-map viewer's geometry
    /// load. Public because the viewer lives in WhereUI, above RegionKit.
    public static let geometryCatalog = root(RegionGeometryCatalogLog.self)
}
