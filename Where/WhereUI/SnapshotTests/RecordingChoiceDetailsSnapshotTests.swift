import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingChoiceDetailsSnapshotTests {
    @Test func recordingChoiceDetails() async {
        await assertSnapshots(of: RecordingChoiceDetails.self)
    }
}
