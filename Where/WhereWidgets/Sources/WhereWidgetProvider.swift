import PeriscopeCore
import WhereCore
import WidgetKit

struct WhereWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let theme: WhereTheme

    init(date: Date, snapshot: WidgetSnapshot, theme: WhereTheme = .standard) {
        self.date = date
        self.snapshot = snapshot
        self.theme = theme
    }
}

/// Shared timeline provider for every Where widget. Reads the latest
/// `WidgetSnapshot` the app published to the shared App Group file
/// (`WidgetSnapshotStore`) — the widget never opens the SwiftData store
/// itself. Asks to be re-run after the next midnight so `date` stays fresh
/// even if the app never wakes; the snapshot's data is refreshed by the app
/// process after each committed write (see `WidgetTimelineRefreshing`).
struct WhereWidgetProvider: TimelineProvider {
    private static let logger = WhereLog.root(WhereWidgetsLog.self)
    private static let calendar = WidgetSnapshotFixtures.calendar
    let appGroupIdentifier: String

    func placeholder(in _: Context) -> WhereWidgetEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (WhereWidgetEntry) -> Void) {
        // The widget gallery wants believable content immediately, not a
        // read of what may be an empty (never-published) snapshot.
        if context.isPreview {
            completion(.sample)
            return
        }
        completion(loadEntry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<WhereWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let nextMidnight = Self.calendar.date(
            byAdding: .day,
            value: 1,
            to: Self.calendar.startOfDay(for: entry.date),
        ) ?? entry.date.addingTimeInterval(24 * 60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    /// Read the latest published snapshot. When none exists yet (fresh
    /// install, unreadable file) we render an empty snapshot rather than
    /// failing. We deliberately do *not* invalidate a snapshot whose `day`
    /// has rolled past today — slightly stale data beats showing nothing.
    private func loadEntry() -> WhereWidgetEntry {
        let now = Date()
        var theme = WhereTheme.standard
        do {
            let store = try WidgetSnapshotStore.shared(
                appGroupIdentifier: appGroupIdentifier,
            )
            theme = try WidgetPresentationStore.shared(
                appGroupIdentifier: appGroupIdentifier,
            ).readTheme()
            if let snapshot = store.read() {
                return WhereWidgetEntry(date: now, snapshot: snapshot, theme: theme)
            }
            Self.logger { .noPublishedSnapshot }
        } catch {
            Self.logger(attachments: [.error(error, name: "app-group-error")]) {
                .appGroupUnavailable(description: String(describing: error))
            }
        }
        return WhereWidgetEntry(
            date: now,
            snapshot: WidgetSnapshotFixtures.emptySnapshot(referenceDate: now),
            theme: theme,
        )
    }
}

extension WhereWidgetEntry {
    /// Believable fixture for placeholders and the widget gallery.
    static var sample: WhereWidgetEntry {
        let now = Date()
        return WhereWidgetEntry(
            date: now,
            snapshot: WidgetSnapshotFixtures.snapshot(
                dayRegions: [.california],
                totals: [.california: 132, .newYork: 41, .canada: 9],
                referenceDate: now,
            ),
            theme: .standard,
        )
    }
}
