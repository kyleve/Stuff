import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct OnboardingIntroPageSnapshotTests {
    @Test func pages() async {
        await assertSnapshots(of: OnboardingIntroPage.self)
    }
}
