import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct FlightDayDetailViewSnapshotTests {
    @Test func flightDayDetail() async {
        await assertSnapshots(of: FlightDayDetailView.self)
    }
}
