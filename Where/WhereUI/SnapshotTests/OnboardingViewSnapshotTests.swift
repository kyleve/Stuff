import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct OnboardingViewSnapshotTests {
    @Test func onboarding() async {
        await assertSnapshots(of: OnboardingView.self)
    }
}
