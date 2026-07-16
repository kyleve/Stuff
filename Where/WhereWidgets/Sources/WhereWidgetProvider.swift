import LogKit
import WhereCore
import WhereUI
import WidgetKit

struct WhereWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Shared timeline provider for every Where widget. Reads the latest
/// `WidgetSnapshot` the app published to the shared App Group file
/// (`WidgetSnapshotStore`) — the widget never opens the SwiftData store
/// itself. Asks to be re-run after the next midnight so `date` stays fresh
/// even if the app never wakes; the snapshot's data is refreshed by the app
/// process after each committed write (see `WidgetTimelineRefreshing`).
struct WhereWidgetProvider: TimelineProvider {
    private static let logger = WhereLog.channel(.whereWidgets)
    private static let calendar = WidgetSnapshotFixtures.calendar

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
        do {
            let store = try WidgetSnapshotStore.shared()
            if let snapshot = store.read() {
                // The widget process has no `WhereSession` to seed the styling
                // registry from the store, so feed it the picked appearances the
                // snapshot carries — this is what makes `region.style` render the
                // user's chosen color/emoji/icon in the widget.
                RegionStyleRegistry.shared.replaceAll(snapshot.appearances)
                return WhereWidgetEntry(date: now, snapshot: snapshot)
            }
            Self.logger.warning("No published widget snapshot; rendering empty state")
        } catch {
            Self.logger.error("Widget App Group unavailable: \(error)")
        }
        return WhereWidgetEntry(
            date: now,
            snapshot: WidgetSnapshotFixtures.emptySnapshot(referenceDate: now),
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
        )
    }
}
