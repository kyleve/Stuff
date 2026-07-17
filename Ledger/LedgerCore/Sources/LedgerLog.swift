import LogKit

/// Central logging facade for the Ledger menu bar app. Every logger site
/// routes through ``channel(_:)`` so messages reach Apple unified logging
/// (Console.app, subsystem `com.stuff.ledger`) and — in DEBUG builds — the
/// shared in-memory ``LogKit/LogStore``.
///
/// Categories are a typed enum rather than raw strings so a new logger can't
/// silently typo into an untracked category.
public enum LedgerLog {
    /// The subsystem every Ledger log shares.
    public static let subsystem = "com.stuff.ledger"

    /// Process-wide buffer. Logging is inherently process-global, so a single
    /// shared store is the natural home.
    public static let store = LogStore()

    public enum Category: String, CaseIterable, Sendable {
        case app = "LedgerApp"
        case configStore = "LedgerConfigStore"
        case keychain = "KeychainStore"
        case services = "LedgerServices"
        case spendAPI = "CursorSpendAPI"
    }

    /// A logging channel for `category`, wired to the shared buffer.
    public static func channel(_ category: Category) -> LogChannel {
        LogChannel(subsystem: subsystem, category: category.rawValue, store: store)
    }
}
