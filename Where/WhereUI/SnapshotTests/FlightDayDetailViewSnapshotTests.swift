import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct FlightDayDetailViewSnapshotTests {
    @Test func flightDayDetail() async {
        await assertSnapshots(of: FlightDayDetailView.self)
    }
}
