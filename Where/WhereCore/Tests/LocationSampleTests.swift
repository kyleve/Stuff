import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct LocationSampleTests {
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

    @Test func tenureStampSurvivesCodableWithoutDroppingLegacyOutboxIdentity() throws {
        let deviceID = RecordingDeviceID(rawValue: UUID())
        let sample = LocationSample(
            timestamp: Date(),
            coordinate: .init(latitude: 40, longitude: -100),
            horizontalAccuracy: 5,
            source: .gpsVisit,
            recordingDeviceID: deviceID,
        )
        let legacyData = try JSONEncoder().encode(sample)
        #expect(try JSONDecoder().decode(LocationSample.self, from: legacyData)
            .recordingDeviceID == deviceID)
        let owner = RecordingAuthority.Owner(deviceID: deviceID, tenureID: .init(rawValue: UUID()))
        let stamped = sample.recorded(under: owner)
        #expect(try JSONDecoder()
            .decode(LocationSample.self, from: JSONEncoder().encode(stamped)) == stamped)
        #expect(stamped.recordingProvenance?.tenureID == owner.tenureID)
    }
}
