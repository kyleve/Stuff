import LogKit
import PeriscopeCore

/// Phantom root event naming the Where app's log scope tree. It is never
/// emitted — its only job is to give ``WhereLog``'s root `Log` the scope name
/// `"Where"`, so every app event sits under one filterable subtree in the
/// process-wide `Periscope.shared` system.
public struct WhereRoot: LogEvent {
    public static let eventName = "Where"
    public var message: String {
        ""
    }
}

/// Central logging facade for the Where app and its modules.
///
/// Every logger derives from one `"Where"` root `Log` and emits into the
/// process-wide Periscope system (``Periscope/shared``). Collaborators that
/// belong together sit under a shared group scope (``location``, ``reminders``,
/// ``backup``, ``widgets``, ``session``, ``evidence``, ``recentActivity``);
/// everything else hangs directly off ``root``. A collaborator derives its own
/// typed leaf — `WhereLog.location(LocationIngestorLog.self)` — so its events
/// carry a structured payload the log viewer can decode, and the loggers form a
/// hierarchy the viewer can filter or inspect by subtree.
///
/// Upper layers (WhereUI, the extensions) derive their own leaves from the same
/// group/root loggers with event types they define locally, so `WhereLog` never
/// needs to know their event shapes.
public enum WhereLog {
    // MARK: Periscope log tree

    /// The `"Where"` root every app logger descends from.
    public static let root = Log<WhereRoot>(system: .shared)

    /// GPS ingestion collaborators (`LocationIngestor`, `LocationOutbox`).
    public static let location = group(.location)
    /// Notification schedulers/reconcilers (logging reminders, daily summary,
    /// data-issue alerts).
    public static let reminders = group(.reminders)
    /// Backup export/import (`BackupCoordinator`, `BackupService`).
    public static let backup = group(.backup)
    /// In-app widget snapshot publishing (`WidgetSnapshotPublisher`,
    /// `WidgetTimelineRefresher`).
    public static let widgets = group(.widgets)
    /// The always-on session coordinator and its scope-tiered view models.
    public static let session = group(.session)
    /// Evidence capture/list/detail view models.
    public static let evidence = group(.evidence)
    /// On-device recent-activity summarization.
    public static let recentActivity = group(.recentActivity)

    private static func group(_ area: Area) -> Log<WhereRoot> {
        root(for: area)
    }

    /// The intermediate grouping scopes under ``root``. A plain `Hashable`
    /// token whose case name becomes the scope name (`location`, `reminders`, …).
    enum Area: Hashable {
        case location
        case reminders
        case backup
        case widgets
        case session
        case evidence
        case recentActivity
    }

    // MARK: Legacy LogKit facade

    // Retained during the Periscope migration so not-yet-migrated call sites
    // (WhereUI's developer log viewer, the app extensions) keep compiling.
    // Removed, along with the LogKit dependency, once every consumer has moved
    // to the Periscope tree above.

    /// The subsystem every legacy Where log shares.
    public static let subsystem = "com.stuff.where"

    /// Process-wide buffer feeding the legacy in-app log viewer.
    public static let store = LogStore()

    public enum Category: String, CaseIterable, Sendable {
        case backupService = "BackupService"
        case dailySummaryReconciler = "DailySummaryReconciler"
        case dailySummaryScheduler = "DailySummaryScheduler"
        case dataIssueAlertReconciler = "DataIssueAlertReconciler"
        case dataIssueAlertScheduler = "DataIssueAlertScheduler"
        case dayJournal = "DayJournal"
        case evidence = "Evidence"
        case launch = "WhereLaunch"
        case locationIngestor = "LocationIngestor"
        case locationOutbox = "LocationOutbox"
        case loggingReminderScheduler = "LoggingReminderScheduler"
        case model = "WhereModel"
        case recentActivitySummarizer = "RecentActivitySummarizer"
        case regionAttribution = "RegionAttribution"
        case reminderReconciler = "ReminderReconciler"
        case session = "WhereSession"
        case shareExtension = "WhereShareExtension"
        case swiftDataStore = "SwiftDataStore"
        case whereIntents = "WhereIntents"
        case widgetRefresher = "WidgetRefresher"
        case widgetSnapshotPublisher = "WidgetSnapshotPublisher"
        case whereWidgets = "WhereWidgets"
    }

    /// A legacy logging channel for `category`, wired to the shared buffer.
    public static func channel(_ category: Category) -> LogChannel {
        LogChannel(subsystem: subsystem, category: category.rawValue, store: store)
    }
}
