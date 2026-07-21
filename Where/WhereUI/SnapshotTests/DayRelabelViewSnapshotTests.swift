import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `DayRelabelView`; the matrix is declared via
/// `SnapshotProviding` in `DayRelabelView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct DayRelabelViewSnapshotTests {
    @Test func dayRelabel() async {
        await assertSnapshots(of: DayRelabelView.self)
    }
}
