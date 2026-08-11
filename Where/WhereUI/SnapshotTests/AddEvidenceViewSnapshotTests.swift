import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct AddEvidenceViewSnapshotTests {
    @Test func addEvidence() async {
        await assertSnapshots(of: AddEvidenceView.self)
    }
}
