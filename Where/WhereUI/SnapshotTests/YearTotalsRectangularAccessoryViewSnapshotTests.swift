import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `YearTotalsRectangularAccessoryView`; the matrix is
/// declared via `SnapshotProviding` in `YearTotalsRectangularAccessoryView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct YearTotalsRectangularAccessoryViewSnapshotTests {
    @Test func yearTotalsRectangularAccessory() async {
        await assertSnapshots(of: YearTotalsRectangularAccessoryView.self)
    }
}
