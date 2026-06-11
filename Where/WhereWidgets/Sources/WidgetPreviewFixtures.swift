#if DEBUG
    import Foundation
    import WhereCore

    /// Sample timeline entries for the widget `#Preview`s (DEBUG-only).
    /// `WhereWidgetEntry.sample` (the single-region, gallery fixture) lives in
    /// `WhereWidgetProvider` since it's also used at runtime; these add the
    /// multi-region and empty states the previews want to exercise.
    extension WhereWidgetEntry {
        /// A multi-region day (CA + NY) so the Today accessories show their
        /// joined / overflow rendering.
        static var previewMultiRegion: WhereWidgetEntry {
            entry(dayRegions: [.california, .newYork], totals: [.california: 132, .newYork: 41])
        }

        /// Nothing logged yet — exercises every widget's empty state.
        static var previewEmpty: WhereWidgetEntry {
            entry(dayRegions: [], totals: [:])
        }

        private static func entry(
            dayRegions: Set<Region>,
            totals: [Region: Int],
        ) -> WhereWidgetEntry {
            let calendar = DayAggregator().calendar
            let day = calendar.startOfDay(for: .now)
            return WhereWidgetEntry(
                date: .now,
                snapshot: WidgetSnapshot(
                    day: day,
                    year: calendar.component(.year, from: day),
                    dayRegions: dayRegions,
                    totals: totals,
                ),
            )
        }
    }
#endif
