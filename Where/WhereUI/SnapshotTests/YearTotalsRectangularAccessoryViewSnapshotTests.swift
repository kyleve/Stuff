import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct YearTotalsRectangularAccessoryViewSnapshotTests {
    @Test func yearTotalsRectangularAccessory() async {
        await assertSnapshots(of: YearTotalsRectangularAccessoryView.self)
    }
}
