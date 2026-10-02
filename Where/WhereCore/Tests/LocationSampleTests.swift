import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct LocationSampleTests {
    @Test func readsExistingUUIDSamplesWithoutChangingTheirWireShape() throws {
        let uuid = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let json = """
        {"id":"\(uuid)","timestamp":1234,
         "coordinate":{"latitude":40,"longitude":-100},
         "horizontalAccuracy":10,"source":{"gpsVisit":{}}}
        """
        let sample = try JSONDecoder().decode(LocationSample.self, from: Data(json.utf8))
        #expect(sample.id.rawValue.uuidString == uuid)
        #expect(sample.coordinate == Coordinate(latitude: 40, longitude: -100))
        let encoded = try JSONEncoder().encode(sample)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["id"] as? String == uuid)
    }

    @Test func stampingTheRecordingDevicePreservesRawMotion() throws {
        let motion = LocationMotion(
            speed: .init(metersPerSecond: 220, accuracyMetersPerSecond: 1.5),
            altitude: .init(meters: 10500, accuracyMeters: 12),
        )
        let sample = LocationSample(
            timestamp: Date(timeIntervalSince1970: 1000),
            coordinate: Coordinate(latitude: 40, longitude: -100),
            horizontalAccuracy: 10,
            source: .gpsSignificantChange,
            motion: motion,
        )
        let deviceID = RecordingDeviceID(rawValue: UUID())
        let stamped = sample.recorded(by: deviceID)
        #expect(stamped.id == sample.id)
        #expect(stamped.motion == motion)
        #expect(stamped.recordingDeviceID == deviceID)
        #expect(try JSONDecoder()
            .decode(LocationSample.self, from: JSONEncoder().encode(stamped)) == stamped)
    }
}
