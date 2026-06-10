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
        .configurationDisplayName("Day Counts")
        .description("Days spent in each region this year.")
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
            default:
                YearTotalsWidgetView(
                    snapshot: entry.snapshot,
                    maxRows: family == .systemMedium ? 5 : 4,
                )
                .containerBackground(.background, for: .widget)
        }
    }
}
