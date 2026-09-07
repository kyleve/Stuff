import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RankingAnimationLabViewSnapshotTests {
    @Test func rankingAnimationLab() async {
        await assertSnapshots(of: RankingAnimationLabView.self)
    }
}
