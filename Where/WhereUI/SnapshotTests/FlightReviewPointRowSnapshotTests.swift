import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct FlightReviewPointRowSnapshotTests {
    @Test func flightReviewPointRow() async {
        await assertSnapshots(of: FlightReviewPointRow.self)
    }
}
