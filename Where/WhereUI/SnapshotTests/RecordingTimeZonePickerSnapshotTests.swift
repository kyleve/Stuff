import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingTimeZonePickerSnapshotTests {
    @Test func recordingTimeZone() async {
        await assertSnapshots(of: RecordingTimeZonePicker.self)
    }
}
