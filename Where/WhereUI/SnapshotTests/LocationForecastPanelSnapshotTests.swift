import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LocationForecastPanelSnapshotTests {
    @Test func componentThemesLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<LocationForecastPanel>.self,
            testName: "componentThemes()",
        )
    }

    @Test func componentThemesExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<LocationForecastPanel>.self,
            testName: "componentThemes()",
        )
    }
}

extension LocationForecastPanel: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Expanded"]
    }
}
