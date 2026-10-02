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
    func publish(_ snapshot: WidgetSnapshot) async throws
    /// Publish access metadata independently so failures can withdraw a cached snapshot.
    func publishCompatibility(_ snapshot: WidgetCompatibilitySnapshot) async throws
}

/// A `WidgetTimelineRefreshing` that does nothing. For SwiftUI previews and
/// tests that need a controller without touching the App Group or
/// `WidgetCenter`.
public struct NoopWidgetTimelineRefresher: WidgetTimelineRefreshing {
    public init() {}

    public func publish(_: WidgetSnapshot) async {}
    public func publishCompatibility(_: WidgetCompatibilitySnapshot) async {}
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

    public func publish(_ snapshot: WidgetSnapshot) async throws {
        do {
            try WidgetSnapshotStore.shared(appGroupIdentifier: appGroupIdentifier).write(snapshot)
            Self.logger { .wroteSnapshot }
        } catch {
            Self.logger { .publishFailed(description: error.localizedDescription) }
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func publishCompatibility(_ snapshot: WidgetCompatibilitySnapshot) async throws {
        do {
            try WidgetCompatibilityStore.shared(appGroupIdentifier: appGroupIdentifier)
                .write(snapshot)
        } catch {
            Self.logger { .publishFailed(description: error.localizedDescription) }
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
