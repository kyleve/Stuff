import SwiftUI
import WidgetKit

/// Entry point for the Where widget extension: today's region(s) and the
/// year-to-date day counts. Both widgets read the shared App Group store
/// the app writes; see `WhereWidgetProvider` for the data path.
@main
struct WhereWidgetsBundle: WidgetBundle {
    private let buildEnvironment = WhereWidgetBuildEnvironment.current()

    var body: some Widget {
        TodayWidget(appGroupIdentifier: buildEnvironment.appGroupIdentifier)
        YearTotalsWidget(appGroupIdentifier: buildEnvironment.appGroupIdentifier)
    }
}

#if DEBUG
    #Preview("Where widgets", as: .systemSmall) {
        TodayWidget(appGroupIdentifier: "group.com.stuff.where.preview")
    } timeline: {
        WhereWidgetEntry.sample
    }
#endif
