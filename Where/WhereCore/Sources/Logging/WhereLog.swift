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
/// ``backup``, ``widgets``, ``session``, ``evidence``);
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
    /// The read/derive path everything else consumes: year reports, calendar
    /// layout, and the data-issue scan. Mostly a span subtree — these
    /// collaborators throw their failures rather than logging them, so what's
    /// worth recording about them is what they *cost*.
    public static let reporting = group(.reporting)

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
        case reporting
    }
}
