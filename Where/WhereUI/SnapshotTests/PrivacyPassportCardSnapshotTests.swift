import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PrivacyPassportCardSnapshotTests {
    @Test func componentThemes() async {
        await assertSnapshots(of: PrivacyPassportCard.self)
    }
}
