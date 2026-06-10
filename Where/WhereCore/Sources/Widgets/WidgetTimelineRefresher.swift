import WidgetKit

/// Pokes WidgetKit to rebuild the app's widget timelines after the store
/// changes, so the widgets repaint from fresh data instead of waiting for
/// the system's own refresh budget. Behind a protocol so `WhereController`
/// can be driven deterministically from tests (same pattern as
/// `LoggingReminderScheduling`).
public protocol WidgetTimelineRefreshing: Sendable {
    /// Ask WidgetKit to re-request the timeline for every widget this app
    /// provides. Called after each committed store mutation that can change
    /// what a widget displays.
    func reloadTimelines() async
}

/// A `WidgetTimelineRefreshing` that does nothing. For SwiftUI previews and
/// tests that need a controller without touching `WidgetCenter`.
public struct NoopWidgetTimelineRefresher: WidgetTimelineRefreshing {
    public init() {}

    public func reloadTimelines() async {}
}

/// Production `WidgetTimelineRefreshing` backed by `WidgetCenter`.
/// Reloads all timelines rather than per-kind: every Where widget renders
/// from the same store, so any committed change can affect all of them.
public struct WidgetCenterTimelineRefresher: WidgetTimelineRefreshing {
    public init() {}

    public func reloadTimelines() async {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
