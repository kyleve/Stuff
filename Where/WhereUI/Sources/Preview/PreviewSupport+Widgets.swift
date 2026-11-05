#if DEBUG
    import Foundation
    import RegionKit
    import WhereCore

    extension PreviewSupport {
        /// A widget snapshot built from the sample year totals, for widget previews and tests.
        public static func sampleWidgetSnapshot(
            dayRegions: Set<Region> = [.california],
            totals: [Region: Int]? = nil,
            day: Date = PreviewSupport.referenceWidgetDay,
        ) -> WidgetSnapshot {
            WidgetSnapshot(
                day: CalendarDay(from: day, in: DayAggregator().calendar),
                version: DataCompatibilityPolicy.foundation.current,
                dayRegions: .complete(dayRegions),
                totals: .complete(totals ?? [
                    .california: 132,
                    .newYork: 41,
                    .canada: 9,
                    .europeanUnion: 4,
                    .other: 2,
                ]),
            )
        }

        static func widgetSnapshotNeedingReview() -> WidgetSnapshot {
            WidgetSnapshot(
                day: CalendarDay(from: referenceWidgetDay, in: DayAggregator().calendar),
                version: RecordingEvidencePolicy.version,
                dayRegions: .needsReview,
                totals: .needsReview,
            )
        }

        static func unavailableWidgetSnapshot() -> WidgetSnapshot {
            WidgetSnapshot(
                day: CalendarDay(from: referenceWidgetDay, in: DayAggregator().calendar),
                history: .unavailable,
            )
        }
    }
#endif
