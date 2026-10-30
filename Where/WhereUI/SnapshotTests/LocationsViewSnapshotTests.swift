import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LocationsViewSnapshotTests {
    @Test func seasonalDocuments() async {
        await assertSnapshots(of: LocationsView.SeasonalThemes.self)
    }

    @Test func locationsLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<LocationsView>.self,
            testName: "locations()",
        )
    }

    @Test func locationsExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<LocationsView>.self,
            testName: "locations()",
        )
    }
}

extension LocationsView: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Loaded", "FlatLoaded"]
    }
}
