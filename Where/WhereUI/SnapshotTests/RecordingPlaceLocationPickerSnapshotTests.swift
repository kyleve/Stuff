import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingPlaceLocationPickerSnapshotTests {
    @Test func recordingPlaceLocationPicker() async {
        await assertSnapshots(of: RecordingPlaceLocationPicker.self)
    }
}
