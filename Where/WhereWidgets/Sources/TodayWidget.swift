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
                // Seed the Broadway context so the shared WhereUI content views
                // resolve trait-aware `@Environment(\.stylesheet)` tokens instead
                // of falling back to `WhereStylesheet.default` (the extension has
                // no other Broadway root), plus the region looks the snapshot
                // carries so `\.regionStyles` renders the user's picks.
                .whereBroadwayRoot(
                    regionStyles: RegionStyleResolver(appearances: entry.snapshot.appearances),
                )
        }
        .configurationDisplayName(String(localized: .widgetGalleryTodayName))
        .description(String(localized: .widgetGalleryTodayDescription))
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
            case .systemSmall:
                TodayWidgetView(snapshot: entry.snapshot)
                    .containerBackground(.background, for: .widget)
            case .systemMedium, .systemLarge, .systemExtraLarge, .systemExtraLargePortrait,
                 .accessoryRectangular, .accessoryCorner:
                TodayWidgetView(snapshot: entry.snapshot)
                    .containerBackground(.background, for: .widget)
            @unknown default:
                TodayWidgetView(snapshot: entry.snapshot)
                    .containerBackground(.background, for: .widget)
        }
    }
}

#if DEBUG
    #Preview("Small", as: .systemSmall) {
        TodayWidget()
    } timeline: {
        WhereWidgetEntry.sample
        WhereWidgetEntry.previewMultiRegion
        WhereWidgetEntry.previewEmpty
    }

    #Preview("Inline", as: .accessoryInline) {
        TodayWidget()
    } timeline: {
        WhereWidgetEntry.previewMultiRegion
        WhereWidgetEntry.previewEmpty
    }

    #Preview("Circular", as: .accessoryCircular) {
        TodayWidget()
    } timeline: {
        WhereWidgetEntry.previewMultiRegion
        WhereWidgetEntry.sample
        WhereWidgetEntry.previewEmpty
    }
#endif
