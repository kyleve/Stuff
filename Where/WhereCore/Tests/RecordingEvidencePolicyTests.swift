import Testing
@testable import WhereCore

struct RecordingEvidencePolicyTests {
    @Test(arguments: [599.999, 600.0])
    func movementRequiresTheWholeMinimumDuration(duration: Double) throws {
        let observations = try [0.0, duration / 2, duration].enumerated().map { index, seconds in
            try RecordingAssessmentTestSupport.observation(
                seconds: seconds,
                longitude: -122 + Double(index) * 0.02,
            )
        }
        let result = try RecordingTrackAssessment.assess(observations: observations, places: [])
        #expect(result.activity == (duration == 600 ? .moving : .insufficient))
    }

    @Test(arguments: [1800.0, 1800.001])
    func connectedEvidenceIncludesTheMaximumGapButNotLongerGaps(gap: Double) throws {
        let observations = try [0.0, gap, gap * 2].map {
            try RecordingAssessmentTestSupport.observation(seconds: $0)
        }
        let result = try RecordingTrackAssessment.assess(observations: observations, places: [])
        #expect(result.activity == (gap == 1800 ? .stationary : .insufficient))
    }

    @Test(arguments: [1199.999, 1200.0])
    func positiveDwellRequiresTheWholeMinimumDuration(duration: Double) throws {
        let observations = try [0.0, duration / 2, duration].map {
            try RecordingAssessmentTestSupport.observation(seconds: $0)
        }
        let result = try RecordingTrackAssessment.assess(observations: observations, places: [])
        #expect(result.activity == (duration == 1200 ? .stationary : .insufficient))
    }

    @Test func nearbyNoiseDoesNotEstablishMovement() throws {
        let observations = try [0.0, 600, 1200].enumerated().map { index, seconds in
            try RecordingAssessmentTestSupport.observation(
                seconds: seconds,
                longitude: -122 + Double(index) * 0.0001,
            )
        }
        #expect(try RecordingTrackAssessment.assess(observations: observations, places: [])
            .activity == .stationary)
    }

    @Test func positionsTooCoarseForEvidenceRemainAvailableButDoNotEstablishMovement() throws {
        let observations = try [0.0, 600, 1200].enumerated().map { index, seconds in
            try RecordingAssessmentTestSupport.observation(
                seconds: seconds,
                longitude: -122 + Double(index) * 0.02,
                accuracy: 251,
            )
        }
        #expect(try RecordingTrackAssessment.assess(observations: observations, places: [])
            .activity == .insufficient)
    }
}
