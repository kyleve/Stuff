import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct RecordingTrackAssessmentTests {
    @Test(arguments: [0, 2])
    func oneDistantEndpointDoesNotEstablishMovement(outlierIndex: Int) throws {
        let observations = try (0 ... 2).map { index in
            try RecordingAssessmentTestSupport.observation(
                seconds: Double(index) * 600,
                longitude: index == outlierIndex ? -121.96 : -122,
            )
        }
        #expect(try RecordingTrackAssessment.assess(observations: observations, places: [])
            .activity == .insufficient)
    }

    @Test func coherentProgressAndPositiveDwellHaveDifferentEvidence() throws {
        let moving = try RecordingAssessmentTestSupport.track(moving: true)
        let stationary = try RecordingAssessmentTestSupport.track(moving: false)
        #expect(try RecordingTrackAssessment.assess(observations: moving, places: [])
            .activity == .moving)
        #expect(try RecordingTrackAssessment.assess(observations: stationary, places: [])
            .activity == .stationary)
        #expect(try RecordingTrackAssessment.assess(observations: [stationary[0]], places: [])
            .activity == .insufficient)
        #expect(try RecordingTrackAssessment.assess(
            observations: Array(repeating: stationary[0], count: 20),
            places: [],
        ).activity == .insufficient)
    }

    @Test func denseContradictoryObservationsCannotBeDiscardedToInventCoherence() throws {
        let moving = try RecordingAssessmentTestSupport.track(moving: true)
        let jump = try RecordingAssessmentTestSupport.observation(seconds: 1, longitude: 0)
        #expect(try RecordingTrackAssessment.assess(observations: moving + [jump], places: [])
            .activity == .implausible)
    }

    @Test func longGapsAndMixedDevicesCannotEstablishOneTrack() throws {
        let distant = try [0.0, 3600, 7200].map { seconds in
            try RecordingAssessmentTestSupport.observation(seconds: seconds)
        }
        #expect(try RecordingTrackAssessment.assess(observations: distant, places: [])
            .activity == .insufficient)
        let mixed = try RecordingAssessmentTestSupport.track(moving: true)
            + RecordingAssessmentTestSupport.track(
                deviceID: RecordingAssessmentTestSupport.second,
                moving: false,
            )
        #expect(throws: RecordingTrackAssessment.ValidationError.self) {
            try RecordingTrackAssessment.assess(observations: mixed, places: [])
        }
    }

    @Test func placesOnlyCorroborateObservedDwellWithinTheirHistoricalValidity() throws {
        let stationary = try RecordingAssessmentTestSupport.track(moving: false)
        let current = try RecordingPlace(
            id: .init(rawValue: UUID()),
            kind: .regularHome,
            coordinate: Coordinate(latitude: 37, longitude: -122),
            validity: RecordingAssessmentTestSupport.period(0, 1201),
        )
        let future = try RecordingPlace(
            id: .init(rawValue: UUID()),
            kind: .temporaryBase,
            coordinate: current.coordinate,
            validity: RecordingAssessmentTestSupport.period(
                1201,
                2400,
            ),
        )
        let result = try RecordingTrackAssessment.assess(
            observations: stationary,
            places: [current, future],
        )
        #expect(result.corroboratingPlaceIDs == [current.id])
        #expect(try RecordingTrackAssessment.assess(observations: [], places: [current])
            .activity == .insufficient)
    }
}
