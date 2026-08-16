import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PlannedStayEditorSnapshotTests {
    @Test func plannedStayEditor() async {
        await assertSnapshots(of: PlannedStayEditor.self)
    }
}
