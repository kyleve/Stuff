import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct OnboardingViewSnapshotTests {
    @Test func onboarding() async {
        await assertSnapshots(of: OnboardingView.self)
    }
}
