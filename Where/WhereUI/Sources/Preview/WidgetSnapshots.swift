#if DEBUG
    import RegionKit
    import SnapshotKit
    import SwiftUI
    import WhereCore

    // Snapshot matrices for the widget entry views and lock-screen accessories.
    // Fixtures use a fixed day so the captures stay deterministic regardless of
    // when they run.

    private let widgetSnapshotDay = Date(timeIntervalSince1970: 1_770_000_000)

    private func widgetSnapshot(
        dayRegions: Set<Region>,
        totals: [Region: Int],
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            day: widgetSnapshotDay,
            year: PreviewSupport.year,
            dayRegions: dayRegions,
            totals: totals,
        )
    }

    extension TodayWidgetView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "SingleRegion", configurations: .componentDefaults) {
                TodayWidgetView(snapshot: widgetSnapshot(
                    dayRegions: [.california],
                    totals: [.california: 132],
                ))
            }
            whereSnapshot(name: "MultiRegion", configurations: .componentLightDark) {
                TodayWidgetView(snapshot: widgetSnapshot(
                    dayRegions: [.california, .newYork],
                    totals: [.california: 132, .newYork: 41],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark) {
                TodayWidgetView(snapshot: widgetSnapshot(dayRegions: [], totals: [:]))
            }
        }
    }

    extension YearTotalsWidgetView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Ranked", configurations: .componentDefaults) {
                YearTotalsWidgetView(snapshot: widgetSnapshot(
                    dayRegions: [.california],
                    totals: [
                        .california: 132,
                        .newYork: 41,
                        .canada: 9,
                        .europeanUnion: 4,
                        .other: 2,
                    ],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark) {
                YearTotalsWidgetView(snapshot: widgetSnapshot(dayRegions: [], totals: [:]))
            }
        }
    }

    extension TodayInlineAccessoryView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Regions", configurations: .componentLightDark) {
                TodayInlineAccessoryView(snapshot: widgetSnapshot(
                    dayRegions: [.california, .newYork],
                    totals: [.california: 132, .newYork: 41],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark) {
                TodayInlineAccessoryView(snapshot: widgetSnapshot(dayRegions: [], totals: [:]))
            }
        }
    }

    extension TodayCircularAccessoryView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Regions", configurations: .componentLightDark) {
                TodayCircularAccessoryView(snapshot: widgetSnapshot(
                    dayRegions: [.california, .newYork],
                    totals: [.california: 132, .newYork: 41],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark) {
                TodayCircularAccessoryView(snapshot: widgetSnapshot(dayRegions: [], totals: [:]))
            }
        }
    }

    extension YearTotalsRectangularAccessoryView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Ranked", configurations: .componentLightDark) {
                YearTotalsRectangularAccessoryView(snapshot: widgetSnapshot(
                    dayRegions: [.california],
                    totals: [.california: 132, .newYork: 41, .canada: 9, .other: 2],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark) {
                YearTotalsRectangularAccessoryView(snapshot: widgetSnapshot(
                    dayRegions: [],
                    totals: [:],
                ))
            }
        }
    }
#endif
