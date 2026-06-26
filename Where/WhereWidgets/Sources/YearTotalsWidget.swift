import SwiftUI
import WhereUI
import WidgetKit

/// Year-to-date day counts per region: small/medium home-screen widgets
/// plus a rectangular lock-screen accessory. Content views live in
/// `WhereUI`; this wrapper only maps the widget family to a view and row
/// budget.
struct YearTotalsWidget: Widget {
    static let kind = "com.stuff.where.widgets.yearTotals"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WhereWidgetProvider()) { entry in
            YearTotalsWidgetContent(entry: entry)
        }
        .configurationDisplayName(WidgetStrings.yearTotalsGalleryName)
        .description(WidgetStrings.yearTotalsGalleryDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct YearTotalsWidgetContent: View {
    @Environment(\.widgetFamily) private var family

    let entry: WhereWidgetEntry

    var body: some View {
        switch family {
            case .accessoryRectangular:
                YearTotalsRectangularAccessoryView(snapshot: entry.snapshot)
                    .containerBackground(.clear, for: .widget)
            case .systemSmall:
                YearTotalsWidgetView(
                    snapshot: entry.snapshot,
                    maxRows: 4,
                )
                .containerBackground(.background, for: .widget)
            case .systemMedium:
                YearTotalsWidgetView(
                    snapshot: entry.snapshot,
                    maxRows: 5,
                )
                .containerBackground(.background, for: .widget)
            case .systemLarge, .systemExtraLarge, .systemExtraLargePortrait,
                 .accessoryCircular, .accessoryInline, .accessoryCorner:
                YearTotalsWidgetView(
                    snapshot: entry.snapshot,
                    maxRows: 4,
                )
                .containerBackground(.background, for: .widget)
            @unknown default:
                YearTotalsWidgetView(
                    snapshot: entry.snapshot,
                    maxRows: 4,
                )
                .containerBackground(.background, for: .widget)
        }
    }
}

#if DEBUG
    #Preview("Small", as: .systemSmall) {
        YearTotalsWidget()
    } timeline: {
        WhereWidgetEntry.sample
        WhereWidgetEntry.previewEmpty
    }

    #Preview("Medium", as: .systemMedium) {
        YearTotalsWidget()
    } timeline: {
        WhereWidgetEntry.sample
        WhereWidgetEntry.previewEmpty
    }

    #Preview("Rectangular", as: .accessoryRectangular) {
        YearTotalsWidget()
    } timeline: {
        WhereWidgetEntry.sample
        WhereWidgetEntry.previewEmpty
    }
#endif
