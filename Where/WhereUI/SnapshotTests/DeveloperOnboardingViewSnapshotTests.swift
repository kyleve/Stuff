import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DeveloperOnboardingViewSnapshotTests {
    @Test func developerOnboarding() async {
        await assertSnapshots(of: DeveloperOnboardingView.self)
    }
}
