import LogKit

/// Central logging facade for the Where app and its modules. Every logger site
/// routes through ``channel(_:)`` so messages reach both Apple unified logging
/// (Console.app, subsystem `com.stuff.where`) and the shared in-memory
/// ``LogStore`` the in-app debug log viewer reads (DEBUG builds only).
///
/// Categories are a typed enum rather than raw strings so a new logger can't
/// silently typo into an untracked category; the raw values match the
/// historical `os.Logger` category strings exactly, keeping Console.app filters
/// working unchanged.
public enum WhereLog {
    /// The subsystem every Where log shares.
    public static let subsystem = "com.stuff.where"

    /// Process-wide buffer feeding the in-app log viewer. Logging is inherently
    /// process-global, so a single shared store is the natural home. The widget
    /// extension runs in its own process and therefore has a distinct instance.
    public static let store = LogStore()

    public enum Category: String, CaseIterable, Sendable {
        case appDelegate = "AppDelegate"
        case backupService = "BackupService"
        case dailySummaryReconciler = "DailySummaryReconciler"
        case dailySummaryScheduler = "DailySummaryScheduler"
        case dayJournal = "DayJournal"
        case launch = "WhereLaunch"
        case locationIngestor = "LocationIngestor"
        case locationOutbox = "LocationOutbox"
        case loggingReminderScheduler = "LoggingReminderScheduler"
        case model = "WhereModel"
        case recentActivitySummarizer = "RecentActivitySummarizer"
        case regionAttributor = "RegionAttributor"
        case reminderReconciler = "ReminderReconciler"
        case session = "WhereSession"
        case swiftDataStore = "SwiftDataStore"
        case widgetRefresher = "WidgetRefresher"
        case widgetSnapshotPublisher = "WidgetSnapshotPublisher"
        case whereWidgets = "WhereWidgets"
    }

    /// A logging channel for `category`, wired to the shared buffer.
    public static func channel(_ category: Category) -> LogChannel {
        LogChannel(subsystem: subsystem, category: category.rawValue, store: store)
    }
}
