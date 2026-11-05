import Foundation
import RegionKit
import WhereCore

/// Shared calendar and snapshot builders for the widget extension. Keeps
/// `DayAggregator().calendar` in one place for timeline reloads and fixtures.
enum WidgetSnapshotFixtures {
    static let calendar = DayAggregator().calendar

    static func snapshot(
        dayRegions: Set<Region>,
        totals: [Region: Int],
        referenceDate: Date = .now,
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            day: CalendarDay(from: referenceDate, in: calendar),
            version: DataCompatibilityPolicy.foundation.current,
            dayRegions: .complete(dayRegions),
            totals: .complete(totals),
        )
    }

    static func unavailableSnapshot(referenceDate: Date = .now) -> WidgetSnapshot {
        WidgetSnapshot(day: CalendarDay(from: referenceDate, in: calendar), history: .unavailable)
    }
}
