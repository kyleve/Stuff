import LogKit

/// Central logging facade for the Foreman menu bar app. Every logger site
/// routes through ``channel(_:)`` so messages reach Apple unified logging
/// (Console.app, subsystem `com.stuff.foreman`) and — in DEBUG builds — the
/// shared in-memory ``LogKit/LogStore``.
///
/// Categories are a typed enum rather than raw strings so a new logger can't
/// silently typo into an untracked category.
public enum ForemanLog {
    /// The subsystem every Foreman log shares.
    public static let subsystem = "com.stuff.foreman"

    /// Process-wide buffer. Logging is inherently process-global, so a single
    /// shared store is the natural home.
    public static let store = LogStore()

    public enum Category: String, CaseIterable, Sendable {
        case app = "ForemanApp"
        case configStore = "WorkerConfigStore"
        case repo = "Repo"
        case repoDiscovery = "RepoDiscovery"
        case services = "ForemanServices"
        case sleepInhibitor = "SleepInhibitor"
        case worker = "Worker"
    }

    /// A logging channel for `category`, wired to the shared buffer.
    public static func channel(_ category: Category) -> LogChannel {
        LogChannel(subsystem: subsystem, category: category.rawValue, store: store)
    }
}
