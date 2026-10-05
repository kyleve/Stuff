import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct FlightStatusBannerSnapshotTests {
    @Test func flightStatusBanner() async {
        await assertSnapshots(of: FlightStatusBanner.self)
    }
}
