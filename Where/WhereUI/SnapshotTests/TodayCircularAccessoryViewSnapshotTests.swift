import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `TodayCircularAccessoryView`; the matrix is declared via
/// `SnapshotProviding` in `TodayAccessoryViews.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct TodayCircularAccessoryViewSnapshotTests {
    @Test func todayCircularAccessory() async {
        await assertSnapshots(of: TodayCircularAccessoryView.self)
    }
}
