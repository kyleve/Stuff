import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `TodayWidgetView`; the matrix is declared via
/// `SnapshotProviding` in `TodayWidgetView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct TodayWidgetViewSnapshotTests {
    @Test func todayWidget() async {
        await assertSnapshots(of: TodayWidgetView.self)
    }
}
