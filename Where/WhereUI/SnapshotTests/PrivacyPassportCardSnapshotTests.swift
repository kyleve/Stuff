import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PrivacyPassportCardSnapshotTests {
    @Test func componentThemesLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<PrivacyPassportCard>.self,
            testName: "componentThemes()",
        )
    }

    @Test func componentThemesExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<PrivacyPassportCard>.self,
            testName: "componentThemes()",
        )
    }
}

extension PrivacyPassportCard: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["Privacy"]
    }
}
