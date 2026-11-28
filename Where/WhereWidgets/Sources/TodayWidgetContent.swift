import SwiftUI
import WhereUI
import WidgetKit

struct TodayWidgetContent: View {
    @Environment(\.widgetFamily) private var family

    let entry: WhereWidgetEntry

    var body: some View {
        if entry.isBlocked {
            WidgetCompatibilityView(family: family)
        } else {
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
}

#if DEBUG
    #Preview("Small", as: .systemSmall) {
        TodayWidget(appGroupIdentifier: "group.com.stuff.where.preview")
    } timeline: {
        WhereWidgetEntry.sample
        WhereWidgetEntry.previewMultiRegion
        WhereWidgetEntry.previewEmpty
        WhereWidgetEntry.previewBlocked
    }
#endif
