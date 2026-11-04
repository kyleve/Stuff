import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct RecordingObservationTests {
    @Test func GPSRequiresAttributionAndOtherCannotBecomeGeographicAgreement() throws {
        let raw = LocationSample(
            timestamp: RecordingAssessmentTestSupport.time(0),
            coordinate: Coordinate(latitude: 37, longitude: -122),
            horizontalAccuracy: 10,
            source: .gpsVisit,
        )
        #expect(throws: RecordingObservation.ValidationError.self) {
            try RecordingObservation(sample: raw, recordingDay: .unresolved, region: .california)
        }
        #expect(throws: RecordingObservation.ValidationError.self) {
            try RecordingAssessmentTestSupport.observation(seconds: 0, region: .other)
        }
        let unknown = try RecordingAssessmentTestSupport.observation(
            seconds: 0,
            region: nil,
            assignment: .unresolved,
        )
        #expect(unknown.recordingDay == .unresolved)
        #expect(unknown.region == nil)
    }

    @Test(arguments: [-1.0, Double.infinity, Double.nan])
    func rejectsInvalidAccuracy(_ accuracy: Double) {
        #expect(throws: RecordingObservation.ValidationError.self) {
            try RecordingAssessmentTestSupport.observation(seconds: 0, accuracy: accuracy)
        }
    }

    @Test func rejectsAnAssignmentForAnotherObservationDay() {
        #expect(throws: RecordingObservation.ValidationError.self) {
            try RecordingAssessmentTestSupport.observation(
                seconds: 0,
                assignment: .resolved(.init(
                    observedAt: RecordingAssessmentTestSupport.time(86400),
                    timeZone: .gmt,
                )),
            )
        }
    }
}
