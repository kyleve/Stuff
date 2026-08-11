import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct EvidenceDetailViewSnapshotTests {
    @Test func evidenceDetail() async {
        await assertSnapshots(of: EvidenceDetailView.self)
    }
}
