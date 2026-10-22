import SnapshotKitTesting
@testable import SnapshotReviewUI
import Testing

@MainActor @Suite(.serialized)
struct ReviewDetailsViewSnapshotTests {
    @Test func captures() async {
        await assertSnapshots(of: ReviewDetailsView.self)
    }
}
