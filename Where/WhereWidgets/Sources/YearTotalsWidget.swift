import SwiftUI
import WhereUI
import WidgetKit

/// Home-screen widget showing year-to-date day counts per region. Content
/// view lives in `WhereUI` (`YearTotalsWidgetView`); this wrapper only maps
/// the widget family to a row budget.
struct YearTotalsWidget: Widget {
    static let kind = "com.stuff.where.widgets.yearTotals"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WhereWidgetProvider()) { entry in
            YearTotalsWidgetContent(entry: entry)
        }
        .configurationDisplayName("Day Counts")
        .description("Days spent in each region this year.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct YearTotalsWidgetContent: View {
    @Environment(\.widgetFamily) private var family

    let entry: WhereWidgetEntry

    var body: some View {
        YearTotalsWidgetView(
            snapshot: entry.snapshot,
            maxRows: family == .systemMedium ? 5 : 4,
        )
        .containerBackground(.background, for: .widget)
    }
}
