import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingCalendarEditorSnapshotTests {
    @Test func recordingCalendar() async {
        await assertSnapshots(of: RecordingCalendarEditor.self)
    }
}
