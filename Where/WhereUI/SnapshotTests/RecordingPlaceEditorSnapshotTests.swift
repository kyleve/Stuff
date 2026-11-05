import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingPlaceEditorSnapshotTests {
    @Test func recordingPlaceEditor() async {
        await assertSnapshots(of: RecordingPlaceEditor.self)
    }
}
