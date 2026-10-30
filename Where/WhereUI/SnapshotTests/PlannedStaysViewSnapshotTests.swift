import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PlannedStaysViewSnapshotTests {
    @Test func plannedStaysLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<PlannedStaysView>.self,
            testName: "plannedStays()",
        )
    }

    @Test func plannedStaysExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<PlannedStaysView>.self,
            testName: "plannedStays()",
        )
    }
}

extension PlannedStaysView: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Itinerary"]
    }
}
