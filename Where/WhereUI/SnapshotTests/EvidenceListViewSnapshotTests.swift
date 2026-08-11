import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct EvidenceListViewSnapshotTests {
    @Test func evidenceList() async {
        await assertSnapshots(of: EvidenceListView.self)
    }
}
