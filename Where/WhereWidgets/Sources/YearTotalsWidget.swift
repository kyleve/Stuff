import SwiftUI
import WhereUI
import WidgetKit

/// Year-to-date day counts per region: small/medium home-screen widgets
/// plus a rectangular lock-screen accessory. Content views live in
/// `WhereUI`; this wrapper only maps the widget family to a view and row
/// budget.
struct YearTotalsWidget: Widget {
    static let kind = "com.stuff.where.widgets.yearTotals"
    let appGroupIdentifier: String

    init() {
        appGroupIdentifier = WhereWidgetBuildEnvironment.current().appGroupIdentifier
    }

    init(appGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: WhereWidgetProvider(appGroupIdentifier: appGroupIdentifier),
        ) { entry in
            YearTotalsWidgetContent(entry: entry)
                // Seed the Broadway context so the shared WhereUI content views
                // resolve trait-aware `@Environment(\.stylesheet)` tokens instead
                // of falling back to `WhereStylesheet.default` (the extension has
                // no other Broadway root), plus the region looks the snapshot
                // carries so `\.regionStyles` renders the user's picks.
                .whereBroadwayRoot(
                    theme: entry.theme,
                    regionStyles: RegionStyleResolver(appearances: entry.snapshot.appearances),
                )
        }
        .configurationDisplayName(String(localized: .widgetGalleryYearTotalsName))
        .description(String(localized: .widgetGalleryYearTotalsDescription))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

#if DEBUG
    #Preview("Medium", as: .systemMedium) {
        YearTotalsWidget(appGroupIdentifier: "group.com.stuff.where.preview")
    } timeline: {
        WhereWidgetEntry.sample
        WhereWidgetEntry.previewEmpty
        WhereWidgetEntry.previewBlocked
    }

    #Preview("Rectangular", as: .accessoryRectangular) {
        YearTotalsWidget(appGroupIdentifier: "group.com.stuff.where.preview")
    } timeline: {
        WhereWidgetEntry.sample
        WhereWidgetEntry.previewEmpty
        WhereWidgetEntry.previewBlocked
    }
#endif
