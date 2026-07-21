import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `YearTotalsWidgetView`; the matrix is declared via
/// `SnapshotProviding` in `YearTotalsWidgetView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct YearTotalsWidgetViewSnapshotTests {
    @Test func yearTotalsWidget() async {
        await assertSnapshots(of: YearTotalsWidgetView.self)
    }
}
