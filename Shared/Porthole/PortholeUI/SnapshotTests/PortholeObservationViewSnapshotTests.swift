@testable import PortholeUI
import SnapshotKitTesting
import Testing

@MainActor
struct PortholeObservationViewSnapshotTests {
    @Test func observation() async {
        await assertSnapshots(of: PortholeObservationView.self)
    }
}
