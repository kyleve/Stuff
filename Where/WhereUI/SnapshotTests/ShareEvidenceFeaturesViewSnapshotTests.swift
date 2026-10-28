import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct ShareEvidenceFeaturesViewSnapshotTests {
    @Test func shareEvidenceFeatures() async {
        await assertSnapshots(of: ShareEvidenceFeaturesView.self)
    }
}
