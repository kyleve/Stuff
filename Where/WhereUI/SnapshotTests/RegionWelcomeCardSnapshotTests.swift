import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RegionWelcomeCardSnapshotTests {
    @Test func welcomeCard() async {
        await assertSnapshots(of: RegionWelcomeCard.self)
    }
}
