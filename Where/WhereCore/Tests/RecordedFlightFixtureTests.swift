import Foundation
import RegionKit
import Testing
import WhereCore

struct RecordedFlightFixtureTests {
    @Test func retainsSubMicrosecondDatePrecision() throws {
        let date = Date(timeIntervalSinceReferenceDate: 600_000_000.0000001)
        let sample = FlightTrajectoryFixtures.replacing(
            FlightTrajectoryFixtures.sample(1, minutes: 0, east: 0),
            timestamp: date,
        )
        let fixture = RecordedFlightFixture(coordinates: .original, now: date, samples: [sample])
        #expect(try RecordedFlightFixture.decode(fixture.jsonData()) == fixture)
    }

    @Test(arguments: RecordedFlightFixture.Name.allCases)
    func bundledWindowsRetainEveryFieldThroughJSON(name: RecordedFlightFixture.Name) throws {
        let fixture = try RecordedFlightFixture.load(name)
        #expect(fixture.coordinates == .rotated)
        #expect(fixture.samples.isEmpty == false)
        let data = try fixture.jsonData()
        let decoded = try RecordedFlightFixture.decode(data)
        #expect(decoded == fixture)
        #expect(try decoded.jsonData() == data)
    }

    @Test func retainsInvalidSensorValuesInsteadOfDroppingObservations() throws {
        let fixture = RecordedFlightFixture(
            coordinates: .original,
            now: FlightTrajectoryFixtures.start,
            samples: [FlightTrajectoryFixtures.sample(
                1,
                minutes: 0,
                east: 0,
                accuracy: .infinity,
                motion: .init(
                    speed: .init(metersPerSecond: .nan, accuracyMetersPerSecond: -.infinity),
                    altitude: .init(meters: -12.25, accuracyMeters: .nan),
                ),
            )],
        )
        let decoded = try RecordedFlightFixture.decode(fixture.jsonData())
        try #require(decoded.samples.count == 1)
        let sample = try #require(decoded.samples.first)
        #expect(decoded.coordinates == .original)
        #expect(decoded.now == fixture.now)
        #expect(sample.id == fixture.samples[0].id)
        #expect(sample.horizontalAccuracy == .infinity)
        let motion = try #require(sample.motion)
        let speed = try #require(motion.speed)
        let altitude = try #require(motion.altitude)
        #expect(speed.metersPerSecond.isNaN)
        #expect(speed.accuracyMetersPerSecond == -.infinity)
        #expect(altitude.meters == -12.25)
        #expect(altitude.accuracyMeters.isNaN)
    }

    @Test(arguments: [
        "{",
        #"{"now": 0, "samples": []}"#,
        #"{"coordinates": "unknown", "now": 0, "samples": []}"#,
        #"{"coordinates": "rotated", "now": 0, "samples": [{}]}"#,
    ])
    func rejectsMalformedFixtures(json: String) {
        #expect(throws: DecodingError.self) {
            try RecordedFlightFixture.decode(Data(json.utf8))
        }
    }

    @Test func missingFilesSurfaceAnError() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        #expect(throws: CocoaError.self) {
            try RecordedFlightFixture.read(from: url)
        }
    }
}
