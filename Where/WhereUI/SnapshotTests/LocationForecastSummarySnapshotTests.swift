import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LocationForecastSummarySnapshotTests {
    @Test func componentThemesLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<LocationForecastSummary>.self,
            testName: "componentThemes()",
        )
    }

    @Test func componentThemesExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<LocationForecastSummary>.self,
            testName: "componentThemes()",
        )
    }
}

extension LocationForecastSummary: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Collapsed"]
    }
}
