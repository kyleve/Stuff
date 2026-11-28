import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PhotoStayReviewViewSnapshotTests {
    @Test func offer() async {
        await assertSnapshots(of: OnboardingPhotoOffer.self)
    }

    @Test func review() async {
        await assertSnapshots(of: PhotoStayReviewView.self)
    }
}
