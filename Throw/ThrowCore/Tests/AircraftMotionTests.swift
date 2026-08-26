import Testing
@testable import ThrowCore

struct AircraftMotionTests {
    @Test func reportedMotionIdentifiesACompleteProviderVelocity() throws {
        let observation = try ThrowCoreFixture.observation(
            groundSpeedKnots: 360,
            groundTrackDegrees: 90,
        )

        let motion = AircraftMotion.reported(by: observation)

        #expect(motion.horizontalSource == .provider)
        #expect(motion.groundTrack?.degrees == 90)
        #expect(motion.groundSpeedKnots == 360)
    }

    @Test func reportedMotionMarksAPartialVelocityUnavailable() throws {
        let observation = try ThrowCoreFixture.observation(
            groundSpeedKnots: nil,
            groundTrackDegrees: 90,
        )

        let motion = AircraftMotion.reported(by: observation)

        #expect(motion.horizontalSource == .unavailable)
        #expect(motion.groundTrack?.degrees == 90)
        #expect(motion.groundSpeedKnots == nil)
    }

    @Test func turnRateMustStayInsideThePredictionBoundary() {
        #expect(throws: ThrowValidationError.self) {
            try AircraftMotion(
                groundTrack: Bearing(degrees: 90),
                groundSpeedKnots: 360,
                verticalRateFeetPerMinute: nil,
                turnRateDegreesPerSecond: 3.1,
                horizontalSource: .provider,
            )
        }
    }
}
