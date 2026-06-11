import os
import WhereCore
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
    private static let logger = Logger(subsystem: "com.stuff.where", category: "WhereWidgets")

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
        let calendar = DayAggregator().calendar
        let nextMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: entry.date),
        ) ?? entry.date.addingTimeInterval(24 * 60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    /// Read the latest published snapshot. When none exists yet (fresh
    /// install, App Group misconfigured, unreadable file) we render an empty
    /// snapshot rather than failing. We deliberately do *not* invalidate a
    /// snapshot whose `day` has rolled past today — slightly stale data beats
    /// showing nothing.
    private func loadEntry() -> WhereWidgetEntry {
        let now = Date()
        if let snapshot = (try? WidgetSnapshotStore.shared())?.read() {
            return WhereWidgetEntry(date: now, snapshot: snapshot)
        }
        Self.logger.error("No published widget snapshot; rendering empty state")
        let calendar = DayAggregator().calendar
        let day = calendar.startOfDay(for: now)
        return WhereWidgetEntry(
            date: now,
            snapshot: WidgetSnapshot(
                day: day,
                year: calendar.component(.year, from: day),
                dayRegions: [],
                totals: [:],
            ),
        )
    }
}

extension WhereWidgetEntry {
    /// Believable fixture for placeholders and the widget gallery.
    static var sample: WhereWidgetEntry {
        let now = Date()
        let calendar = DayAggregator().calendar
        return WhereWidgetEntry(
            date: now,
            snapshot: WidgetSnapshot(
                day: calendar.startOfDay(for: now),
                year: calendar.component(.year, from: now),
                dayRegions: [.california],
                totals: [.california: 132, .newYork: 41, .canada: 9],
            ),
        )
    }
}
