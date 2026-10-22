import SnapshotKitTesting
@testable import SnapshotReviewUI
import Testing

@MainActor @Suite(.serialized)
struct ReviewImageViewSnapshotTests {
    @Test func captures() async {
        await assertSnapshots(of: ReviewImageView.self)
    }
}
