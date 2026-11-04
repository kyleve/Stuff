import SnapshotKitTesting
import Testing

@MainActor
struct ShareEvidenceViewSnapshotTests {
    @Test func pendingShare() async {
        await assertSnapshots(of: ShareEvidenceView.self)
    }
}
