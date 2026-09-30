import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingFeaturesViewSnapshotTests {
    @Test func gallery() async {
        await assertSnapshots(of: RecordingFeaturesView.self)
    }
}
