import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct YearTotalsRectangularAccessoryViewSnapshotTests {
    @Test func yearTotalsRectangularAccessory() async {
        await assertSnapshots(of: YearTotalsRectangularAccessoryView.self)
    }
}
