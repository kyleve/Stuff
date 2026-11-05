import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingScopeEditorSnapshotTests {
    @Test func recordingScope() async {
        await assertSnapshots(of: RecordingScopeEditor.self)
    }
}
