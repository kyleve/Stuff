import SwiftUI
import WhereUI
import WidgetKit

/// Small home-screen widget showing which region(s) today already counts
/// for. Content view lives in `WhereUI` (`TodayWidgetView`) so it's covered
/// by the hosted test suite.
struct TodayWidget: Widget {
    static let kind = "com.stuff.where.widgets.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WhereWidgetProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Which region today counts for.")
        .supportedFamilies([.systemSmall])
    }
}
