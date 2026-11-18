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
    func publish(_ snapshot: WidgetSnapshot) async
}

/// A `WidgetTimelineRefreshing` that does nothing. For SwiftUI previews and
/// tests that need a controller without touching the App Group or
/// `WidgetCenter`.
public struct NoopWidgetTimelineRefresher: WidgetTimelineRefreshing {
    public init() {}

    public func publish(_: WidgetSnapshot) async {}
}

/// Production `WidgetTimelineRefreshing`: writes the snapshot to the shared
/// App Group file (`WidgetSnapshotStore`) and reloads all timelines. Reloads
/// every kind rather than per-kind because all Where widgets render from the
/// same snapshot, so any committed change can affect all of them.
public struct WidgetCenterTimelineRefresher: WidgetTimelineRefreshing {
    private static let logger = WhereLog.widgets(WidgetTimelineRefresherLog.self)
    private let access: AppGroupDataAccess
    private let coordinator: DataCompatibilityCoordinator
    private let admission: DataCompatibilityAdmission
    private let reloader: any WidgetTimelineReloading

    @MainActor
    public init(
        appGroupIdentifier: String,
        coordinator: DataCompatibilityCoordinator,
        admission: DataCompatibilityAdmission,
    ) {
        access = AppGroupDataAccess(appGroupIdentifier: appGroupIdentifier)
        self.coordinator = coordinator
        self.admission = admission
        reloader = WidgetCenterTimelineReloader()
    }

    @_spi(Testing)
    public init(
        access: AppGroupDataAccess,
        coordinator: DataCompatibilityCoordinator,
        admission: DataCompatibilityAdmission,
        reloader: any WidgetTimelineReloading,
    ) {
        self.access = access
        self.coordinator = coordinator
        self.admission = admission
        self.reloader = reloader
    }

    public func publish(_ snapshot: WidgetSnapshot) async {
        // No suspension between checking this scope's grant and writing its envelope.
        await MainActor.run {
            do {
                try coordinator.requireAccess(admission)
                try access.writeWidgetSnapshot(
                    snapshot,
                    version: coordinator.version,
                    domain: admission.domain,
                )
                Self.logger.wroteSnapshot()
            } catch {
                Self.logger.publishFailed(error: .restricted(.errorDetails, error))
            }
            reloader.reload()
        }
    }
}
