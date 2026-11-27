import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PhotoStayReviewViewSnapshotTests {
    @Test func review() async {
        await assertSnapshots(of: PhotoStayReviewView.self)
    }
}
