import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingIgnoreEditorSnapshotTests {
    @Test func recordingIgnoreEditor() async {
        await assertSnapshots(of: RecordingIgnoreEditor.self)
    }
}
