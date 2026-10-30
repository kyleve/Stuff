import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct ElsewhereViewSnapshotTests {
    @Test func elsewhereLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<ElsewhereView>.self,
            testName: "elsewhere()",
        )
    }

    @Test func elsewhereExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<ElsewhereView>.self,
            testName: "elsewhere()",
        )
    }
}

extension ElsewhereView: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Loaded", "FlatLoaded"]
    }
}
