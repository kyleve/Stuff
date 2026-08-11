import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PrivacyPassportCardSnapshotTests {
    @Test func privacyPassport() async {
        await assertSnapshots(of: PrivacyPassportCard.self)
    }
}
