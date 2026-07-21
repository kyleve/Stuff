import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `LoggedDaysView`; the matrix is declared via
/// `SnapshotProviding` in `LoggedDaysView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct LoggedDaysViewSnapshotTests {
    @Test func loggedDays() async {
        await assertSnapshots(of: LoggedDaysView.self)
    }
}
