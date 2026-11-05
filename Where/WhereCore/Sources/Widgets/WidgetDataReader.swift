import Foundation
import RegionKit

/// Builds one assessed publication for the publisher without exposing store access to widgets.
protocol WidgetSnapshotReading: Sendable {
    func snapshot(asOf date: Date) async throws -> WidgetSnapshot
}

/// Reuses the shared report reader within one store snapshot, including region appearances.
/// Runs in the app process; the widget extension reads only the published App Group file.
public struct WidgetDataReader: WidgetSnapshotReading {
    private let store: any WhereStore
    private let aggregator: DayAggregator
    private let attributor: any RegionAttributing
    let history: LocationHistoryReader

    public init(
        store: any WhereStore,
        history: LocationHistoryReader,
        aggregator: DayAggregator = DayAggregator(),
        attributor: any RegionAttributing = RegionAttributor.shared,
    ) {
        self.store = store
        self.history = history
        self.aggregator = aggregator
        self.attributor = attributor
    }

    /// Build the snapshot for the calendar day containing `date`, reading
    /// that day's year from the store. Same aggregation rules as the app's
    /// year report, so the widget and the app never disagree on a count.
    public func snapshot(asOf date: Date) async throws -> WidgetSnapshot {
        try await store.readSnapshot {
            let calendar = aggregator.calendar
            let calendarDay = CalendarDay(from: date, in: calendar)
            let report = try await ReportReader(
                store: store,
                aggregator: aggregator,
                attributor: attributor,
                history: history,
            ).yearReport(for: calendarDay.year)
            let dayCompleteness = try report.completeness
                .restricted(to: calendarDay ... calendarDay)
            let dayRegions = report.days.first { $0.day == calendarDay }?.regions ?? []
            var appearances: [Region: RegionAppearance] = [:]
            for primary in try await store.primaryRegions() {
                if let appearance = primary.appearance { appearances[primary.region] = appearance }
            }
            return WidgetSnapshot(
                day: calendarDay,
                version: report.completeness.policyVersion,
                dayRegions: dayCompleteness.isComplete ? .complete(dayRegions) : .needsReview,
                totals: report.completeness.isComplete ? .complete(report.totals) : .needsReview,
                appearances: appearances,
            )
        }
    }
}
