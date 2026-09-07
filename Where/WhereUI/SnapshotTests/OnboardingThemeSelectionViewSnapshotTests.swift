import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct OnboardingThemeSelectionViewSnapshotTests {
    @Test func themeSelection() async {
        await assertSnapshots(of: OnboardingThemeSelectionView.self)
    }
}
