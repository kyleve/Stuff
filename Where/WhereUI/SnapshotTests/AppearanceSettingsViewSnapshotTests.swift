import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct AppearanceSettingsViewSnapshotTests {
    @Test func appearanceLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<AppearanceSettingsView>.self,
            testName: "appearance()",
        )
    }

    @Test func appearanceExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<AppearanceSettingsView>.self,
            testName: "appearance()",
        )
    }
}

extension AppearanceSettingsView: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Default", "FlatSelected"]
    }
}
