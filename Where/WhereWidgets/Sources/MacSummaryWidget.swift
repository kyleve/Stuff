#if targetEnvironment(macCatalyst)
    import SwiftUI
    import WhereUI
    import WidgetKit

    /// Mac-only combined glance: today's regions and the leading year-to-date
    /// day counts in one small or medium widget.
    struct MacSummaryWidget: Widget {
        static let kind = "com.stuff.where.widgets.macSummary"

        var body: some WidgetConfiguration {
            StaticConfiguration(kind: Self.kind, provider: WhereWidgetProvider()) { entry in
                MacSummaryWidgetContent(entry: entry)
                    .whereBroadwayRoot(
                        regionStyles: RegionStyleResolver(
                            appearances: entry.snapshot.appearances,
                        ),
                    )
            }
            .configurationDisplayName(String(localized: .widgetGalleryMacSummaryName))
            .description(String(localized: .widgetGalleryMacSummaryDescription))
            .supportedFamilies([.systemSmall, .systemMedium])
        }
    }

    private struct MacSummaryWidgetContent: View {
        @Environment(\.widgetFamily) private var family

        let entry: WhereWidgetEntry

        var body: some View {
            MacSummaryWidgetView(
                snapshot: entry.snapshot,
                layout: family == .systemSmall ? .compact : .wide,
            )
            .containerBackground(.background, for: .widget)
        }
    }

    #if DEBUG
        #Preview("Small", as: .systemSmall) {
            MacSummaryWidget()
        } timeline: {
            WhereWidgetEntry.sample
            WhereWidgetEntry.previewEmpty
        }

        #Preview("Medium", as: .systemMedium) {
            MacSummaryWidget()
        } timeline: {
            WhereWidgetEntry.sample
            WhereWidgetEntry.previewEmpty
        }
    #endif
#endif
