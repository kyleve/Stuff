import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for the widget entry views and lock-screen accessories, each
/// declared via `SnapshotProviding` (see `WidgetSnapshots.swift` in WhereUI).
@MainActor
@Suite(.snapshots(record: .missing))
struct WidgetSnapshotTests {
    @Test func todayWidget() async {
        await assertSnapshots(of: TodayWidgetView.self)
    }

    @Test func yearTotalsWidget() async {
        await assertSnapshots(of: YearTotalsWidgetView.self)
    }

    @Test func todayInlineAccessory() async {
        await assertSnapshots(of: TodayInlineAccessoryView.self)
    }

    @Test func todayCircularAccessory() async {
        await assertSnapshots(of: TodayCircularAccessoryView.self)
    }

    @Test func yearTotalsRectangularAccessory() async {
        await assertSnapshots(of: YearTotalsRectangularAccessoryView.self)
    }
}
