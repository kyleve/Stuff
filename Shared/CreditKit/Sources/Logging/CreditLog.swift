import PeriscopeCore

/// Phantom root event naming CreditKit's log scope tree. It is never emitted —
/// its only job is to give ``CreditLog``'s root `Log` the scope name
/// `"CreditKit"`, so every CreditKit event sits under one filterable subtree.
struct CreditKitRoot: LogEvent {
    static let eventName = "CreditKit"
    var message: String {
        ""
    }
}

/// Logging facade for `CreditKit`. Every logger site derives from one root
/// `Log` scoped `"CreditKit"`, so CreditKit's events form a single subtree
/// under Periscope's process-wide system (``Periscope/shared``).
///
/// CreditKit owns its own root scope rather than borrowing a host app's: it is
/// a standalone lower-level module that must not depend on app code.
enum CreditLog {
    /// The `"CreditKit"` root every CreditKit logger descends from.
    static let root = Log<CreditKitRoot>(system: .shared)

    /// `CreditCatalog` — the bundled `credits.json` manifest load.
    static let catalog = root(CreditCatalogLog.self)

    /// `SoftwareCredit` — vendored license-text loads.
    static let softwareCredit = root(SoftwareCreditLog.self)
}
