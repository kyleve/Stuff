import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct OnboardingThemeSelectionViewSnapshotTests {
    @Test func themeSelectionLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<OnboardingThemeSelectionView>.self,
            testName: "themeSelection()",
        )
    }

    @Test func themeSelectionExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<OnboardingThemeSelectionView>.self,
            testName: "themeSelection()",
        )
    }
}

extension OnboardingThemeSelectionView: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Standard", "Alternate", "Halloween"]
    }
}
