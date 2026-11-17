import PeriscopeCore
import WhereCore
import WidgetKit

enum WhereWidgetContent {
    case available(WidgetSnapshot)
    case absent
    case blocked
}

struct WhereWidgetEntry: TimelineEntry {
    let date: Date
    let content: WhereWidgetContent
    let theme: WhereTheme

    init(date: Date, snapshot: WidgetSnapshot, theme: WhereTheme = .standard) {
        self.init(date: date, content: .available(snapshot), theme: theme)
    }

    init(date: Date, content: WhereWidgetContent, theme: WhereTheme) {
        self.date = date
        self.content = content
        self.theme = theme
    }

    var isBlocked: Bool {
        if case .blocked = content { true } else { false }
    }

    var snapshot: WidgetSnapshot {
        switch content {
            case let .available(snapshot): snapshot
            case .absent, .blocked: WidgetSnapshotFixtures.emptySnapshot(referenceDate: date)
        }
    }
}

/// Shared timeline provider for every Where widget. Reads the latest
/// `WidgetSnapshot` the app published to the shared App Group file
/// through `AppGroupDataAccess` — the widget never opens the SwiftData store
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

    /// Theme publication is independent. History requires a matching verified receipt and envelope.
    private func loadEntry() -> WhereWidgetEntry {
        let now = Date()
        var theme = WhereTheme.standard
        do {
            theme = try WidgetPresentationStore.shared(appGroupIdentifier: appGroupIdentifier)
                .readTheme()
            let access = AppGroupDataAccess(appGroupIdentifier: appGroupIdentifier)
            if let snapshot = try access.readWidgetSnapshot(version: .current) {
                return WhereWidgetEntry(date: now, snapshot: snapshot, theme: theme)
            }
            Self.logger.noPublishedSnapshot()
            return WhereWidgetEntry(date: now, content: .absent, theme: theme)
        } catch {
            Self.logger.compatibilityBlocked(error: .restricted(.errorDetails, error))
            return WhereWidgetEntry(date: now, content: .blocked, theme: theme)
        }
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
