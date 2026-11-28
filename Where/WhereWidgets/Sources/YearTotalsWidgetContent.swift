import SwiftUI
import WhereUI
import WidgetKit

struct YearTotalsWidgetContent: View {
    @Environment(\.widgetFamily) private var family

    let entry: WhereWidgetEntry

    var body: some View {
        if entry.isBlocked {
            WidgetCompatibilityView(family: family)
        } else {
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
}

#if DEBUG
    #Preview("Small", as: .systemSmall) {
        YearTotalsWidget(appGroupIdentifier: "group.com.stuff.where.preview")
    } timeline: {
        WhereWidgetEntry.sample
        WhereWidgetEntry.previewEmpty
        WhereWidgetEntry.previewBlocked
    }
#endif
