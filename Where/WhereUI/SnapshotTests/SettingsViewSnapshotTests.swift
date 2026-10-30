import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct SettingsViewSnapshotTests {
    @Test func settingsLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<SettingsView>.self,
            testName: "settings()",
        )
    }

    @Test func settingsExtended() async {
        await assertSnapshots(of: WhereExtendedSnapshots<SettingsView>.self, testName: "settings()")
    }
}

extension SettingsView: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Default"]
    }
}
