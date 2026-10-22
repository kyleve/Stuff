import SnapshotKitTesting
@_spi(Testing) import SnapshotReviewUI
import Testing

@MainActor @Suite(.serialized)
struct ReviewBrowserSnapshotTests {
    @Test func browser() async {
        await assertSnapshots(of: ReviewBrowserView.self)
    }
}
