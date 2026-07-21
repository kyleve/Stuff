import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `TodayInlineAccessoryView`; the matrix is declared via
/// `SnapshotProviding` in `TodayAccessoryViews.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct TodayInlineAccessoryViewSnapshotTests {
    @Test func todayInlineAccessory() async {
        await assertSnapshots(of: TodayInlineAccessoryView.self)
    }
}
