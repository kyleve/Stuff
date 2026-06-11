import SwiftUI
import WidgetKit

/// Entry point for the Where widget extension: today's region(s) and the
/// year-to-date day counts. Both widgets read the shared App Group store
/// the app writes; see `WhereWidgetProvider` for the data path.
@main
struct WhereWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        YearTotalsWidget()
    }
}
