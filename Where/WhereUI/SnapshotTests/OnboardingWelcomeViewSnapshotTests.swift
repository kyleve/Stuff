import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct OnboardingWelcomeViewSnapshotTests {
    @Test func welcome() async {
        await assertSnapshots(of: OnboardingWelcomeView.self)
    }
}
