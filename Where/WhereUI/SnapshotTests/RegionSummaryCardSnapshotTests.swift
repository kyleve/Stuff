import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RegionSummaryCardSnapshotTests {
    @Test func componentThemesLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<RegionSummaryCard>.self,
            testName: "componentThemes()",
        )
    }

    @Test func componentThemesExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<RegionSummaryCard>.self,
            testName: "componentThemes()",
        )
    }
}

extension RegionSummaryCard: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Regular", "Compact", "Elsewhere"]
    }
}
