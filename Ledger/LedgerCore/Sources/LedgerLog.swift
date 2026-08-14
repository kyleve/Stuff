import PeriscopeCore

/// Root namespace for Ledger's log scope tree.
@LogScope("Ledger")
public enum LedgerRoot {}

/// Central logging facade for the Ledger menu bar app.
///
/// Every logger derives from the one `"Ledger"` root `Log` and emits into the
/// process-wide Periscope system, so the app's events form a filterable subtree.
/// Ledger logs freeform diagnostics (a failed fetch, an unreadable config), so
/// its loggers emit plain messages rather than structured events — see
/// `WhereLog` for the typed-leaf pattern to follow if a payload ever needs to be
/// queryable.
///
/// Scopes are a typed enum rather than raw strings so a new logger can't
/// silently typo into an untracked scope.
public enum LedgerLog {
    /// The `"Ledger"` root every logger descends from.
    public static let root = Log<LedgerRoot>(system: .shared)

    /// The model tree — `LedgerServices` and its collaborators (config, history,
    /// token resolution).
    public static let services = scope(.services)

    /// The Cursor dashboard API client.
    public static let dashboard = scope(.dashboard)

    private static func scope(_ area: Area) -> Log<LedgerRoot> {
        root(for: area)
    }

    /// The grouping scopes under ``root``. A plain `Hashable` token whose case
    /// name becomes the scope name (`services`, `dashboard`).
    enum Area: Hashable {
        case services
        case dashboard
    }
}
