import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RegionWelcomeCardSnapshotTests {
    @Test func regionWelcomeCardLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<RegionWelcomeCard>.self,
            testName: "regionWelcomeCard()",
        )
    }

    @Test func regionWelcomeCardExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<RegionWelcomeCard>.self,
            testName: "regionWelcomeCard()",
        )
    }
}

extension RegionWelcomeCard: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Welcome"]
    }
}
