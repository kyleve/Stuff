import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RegionWelcomeCardSnapshotTests {
    @Test func regionWelcomeCard() async {
        await assertSnapshots(of: RegionWelcomeCard.self)
    }
}
