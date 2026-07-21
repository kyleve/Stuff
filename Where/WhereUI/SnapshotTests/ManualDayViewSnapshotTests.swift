import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `ManualDayView`; the matrix is declared via
/// `SnapshotProviding` in `ManualDayView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct ManualDayViewSnapshotTests {
    @Test func manualDay() async {
        await assertSnapshots(of: ManualDayView.self)
    }
}
