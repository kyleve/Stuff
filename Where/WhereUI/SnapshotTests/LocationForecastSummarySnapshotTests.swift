import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LocationForecastSummarySnapshotTests {
    @Test func componentThemes() async {
        await assertSnapshots(of: LocationForecastSummary.self)
    }
}
