import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct ThrowOnboardingViewSnapshotTests {
    @Test func onboardingSteps() async {
        await assertSnapshots(of: ThrowOnboardingView.self)
    }
}
