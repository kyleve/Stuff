import SwiftUI
import WhereUI
import WidgetKit

/// Which region(s) today already counts for: a small home-screen widget
/// plus inline and circular lock-screen accessories. Content views live in
/// `WhereUI` so they're covered by the hosted test suite; this wrapper only
/// maps the widget family to a view.
struct TodayWidget: Widget {
    static let kind = "com.stuff.where.widgets.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WhereWidgetProvider()) { entry in
            TodayWidgetContent(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Which region today counts for.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular])
    }
}

private struct TodayWidgetContent: View {
    @Environment(\.widgetFamily) private var family

    let entry: WhereWidgetEntry

    var body: some View {
        switch family {
            case .accessoryInline:
                // Inline draws no container; the background modifier is
                // still required for the widget to render on iOS 17+.
                TodayInlineAccessoryView(snapshot: entry.snapshot)
                    .containerBackground(.clear, for: .widget)
            case .accessoryCircular:
                // `TodayCircularAccessoryView` supplies its own
                // `AccessoryWidgetBackground`.
                TodayCircularAccessoryView(snapshot: entry.snapshot)
                    .containerBackground(.clear, for: .widget)
            default:
                TodayWidgetView(snapshot: entry.snapshot)
                    .containerBackground(.background, for: .widget)
        }
    }
}
