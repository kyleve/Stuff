@testable import DaylightUI
import SnapshotKitTesting
import Testing

@MainActor
struct DeliveryRecoveryViewSnapshotTests {
    @Test func screen() async {
        await assertSnapshots(of: DeliveryRecoveryView.self)
    }
}
