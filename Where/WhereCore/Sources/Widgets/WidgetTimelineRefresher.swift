import PeriscopeCore
import WidgetKit

/// Publishes a freshly-computed `WidgetSnapshot` for the widget extension
/// to render, then pokes WidgetKit to reload. Called by `WidgetSnapshotPublisher`
/// after each committed store mutation that can change what a widget shows.
/// Behind a protocol so the publisher can be driven deterministically from
/// tests (same pattern as `LoggingReminderScheduling`).
public protocol WidgetTimelineRefreshing: Sendable {
    /// Persist `snapshot` where the widget process can read it, then ask
    /// WidgetKit to rebuild every timeline.
    func publish(_ snapshot: WidgetSnapshot, access: DataCompatibilityAccess?) async throws

    /// Remove the published history and reload timelines after pending publications drain.
    func withdraw() async
}

extension WidgetTimelineRefreshing {
    /// Unscoped worlds use this entry point. Production services inject a compatibility wrapper
    /// which supplies its access at the actual file-write boundary.
    public func publish(_ snapshot: WidgetSnapshot) async throws {
        try await publish(snapshot, access: nil)
    }
}

/// A `WidgetTimelineRefreshing` that does nothing. For SwiftUI previews and
/// tests that need a controller without touching the App Group or
/// `WidgetCenter`.
public struct NoopWidgetTimelineRefresher: WidgetTimelineRefreshing {
    public init() {}

    public func publish(_: WidgetSnapshot, access _: DataCompatibilityAccess?) async {}

    public func withdraw() async {}
}

/// Production `WidgetTimelineRefreshing`: writes the snapshot to the shared
/// App Group file (`WidgetSnapshotStore`) and reloads all timelines. Reloads
/// every kind rather than per-kind because all Where widgets render from the
/// same snapshot, so any committed change can affect all of them.
public struct WidgetCenterTimelineRefresher: WidgetTimelineRefreshing {
    private static let logger = WhereLog.widgets(WidgetTimelineRefresherLog.self)
    private let appGroupIdentifier: String

    public init(appGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
    }

    public func publish(_ snapshot: WidgetSnapshot, access: DataCompatibilityAccess?) async throws {
        let snapshotStore = try WidgetSnapshotStore.shared(appGroupIdentifier: appGroupIdentifier)
        if let access {
            try access.publishWhileValid { try snapshotStore.write(snapshot) }
        } else {
            try snapshotStore.write(snapshot)
        }
        Self.logger.wroteSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func withdraw() async {
        do {
            try WidgetSnapshotStore.shared(appGroupIdentifier: appGroupIdentifier).withdraw()
        } catch {
            Self.logger.withdrawFailed(error: .restricted(.errorDetails, error))
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
