@testable import DaylightUI
import SnapshotKitTesting
import Testing

@MainActor
struct PhotosRecoveryViewSnapshotTests {
    @Test func screen() async {
        await assertSnapshots(of: PhotosRecoveryView.self)
    }
}
