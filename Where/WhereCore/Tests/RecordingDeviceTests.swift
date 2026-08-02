import Testing
@testable import WhereCore

struct RecordingDeviceTests {
    @Test func phoneRecommendsAutomaticRecording() {
        #expect(RecordingDeviceKind.phone.recommendsAutomaticRecording)
    }

    @Test(arguments: [RecordingDeviceKind.tablet, .other])
    func devicesCommonlyLeftBehindRecommendRecordingOff(kind: RecordingDeviceKind) {
        #expect(kind.recommendsAutomaticRecording == false)
    }
}
