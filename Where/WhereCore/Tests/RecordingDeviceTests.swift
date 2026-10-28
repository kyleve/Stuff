import Foundation
import Testing
@testable import WhereCore

struct RecordingDeviceTests {
    @Test func phoneRecommendsAutomaticRecording() {
        #expect(RecordingDeviceKind.phone.recommendsAutomaticRecording)
    }

    @Test(arguments: [
        RecordingDeviceKind.tablet,
        .computer,
        .watch,
        .other(nil),
    ])
    func devicesCommonlyLeftBehindRecommendRecordingOff(kind: RecordingDeviceKind) {
        #expect(kind.recommendsAutomaticRecording == false)
    }

    @Test func unknownPlatformLabelRoundTripsThroughCodable() throws {
        let kind = RecordingDeviceKind.other("spatial-computer")

        let encoded = try JSONEncoder().encode(kind)
        let decoded = try JSONDecoder().decode(RecordingDeviceKind.self, from: encoded)

        #expect(decoded == kind)
    }

    @Test func synthesizedCodableDecodesUpgradedV3Kinds() throws {
        let decoder = JSONDecoder()

        #expect(try decoder.decode(
            RecordingDeviceKind.self,
            from: Data(#"{"phone":{}}"#.utf8),
        ) == .phone)
        #expect(try decoder.decode(
            RecordingDeviceKind.self,
            from: Data(#"{"other":{}}"#.utf8),
        ) == .other(nil))
    }
}
