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
        let day = calendar.startOfDay(for: referenceDate)
        return WidgetSnapshot(
            day: day,
            year: calendar.component(.year, from: day),
            dayRegions: dayRegions,
            totals: totals,
        )
    }

    static func emptySnapshot(referenceDate: Date = .now) -> WidgetSnapshot {
        snapshot(dayRegions: [], totals: [:], referenceDate: referenceDate)
    }
}
