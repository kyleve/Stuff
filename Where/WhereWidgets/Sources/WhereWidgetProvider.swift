import os
import WhereCore
import WidgetKit

struct WhereWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Shared timeline provider for every Where widget: opens the App Group
/// store read-only, builds one `WidgetSnapshot` for "now", and asks to be
/// re-run after the next midnight so "today" rolls over even if the app
/// never wakes. Fresh data between midnights comes from the app process
/// poking `WidgetCenter` after each committed write (see
/// `WidgetTimelineRefreshing`), not from this timeline.
struct WhereWidgetProvider: TimelineProvider {
    private static let logger = Logger(subsystem: "com.stuff.where", category: "WhereWidgets")

    func placeholder(in _: Context) -> WhereWidgetEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (WhereWidgetEntry) -> Void) {
        // The widget gallery wants believable content immediately, not a
        // disk read of what may be an empty store.
        if context.isPreview {
            completion(.sample)
            return
        }
        Task {
            await completion(loadEntry())
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<WhereWidgetEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let calendar = DayAggregator().calendar
            let nextMidnight = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: entry.date),
            ) ?? entry.date.addingTimeInterval(24 * 60 * 60)
            completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
        }
    }

    /// Read the snapshot from the shared store. Any failure (store not yet
    /// created, App Group misconfigured, corrupt read) degrades to an empty
    /// snapshot so the widget renders its empty state instead of stale or
    /// missing content.
    private func loadEntry() async -> WhereWidgetEntry {
        let now = Date()
        do {
            let store = try SwiftDataStore.readOnly()
            let reader = WidgetDataReader(store: store)
            return try await WhereWidgetEntry(date: now, snapshot: reader.snapshot(asOf: now))
        } catch {
            Self.logger.error(
                "Falling back to an empty snapshot: \(error.localizedDescription, privacy: .public)",
            )
            let calendar = DayAggregator().calendar
            let day = calendar.startOfDay(for: now)
            let snapshot = WidgetSnapshot(
                day: day,
                year: calendar.component(.year, from: day),
                dayRegions: [],
                totals: [:],
            )
            return WhereWidgetEntry(date: now, snapshot: snapshot)
        }
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
