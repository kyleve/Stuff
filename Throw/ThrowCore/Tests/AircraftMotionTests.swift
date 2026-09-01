import Testing
@testable import ThrowCore

struct AircraftMotionTests {
    @Test func resolvedObservationCarriesItsMotion() throws {
        let observation = try ThrowCoreFixture.observation(
            groundSpeedKnots: 360,
            groundTrackDegrees: 90,
        )
        let motion = AircraftMotion.reported(by: observation)
        let resolved = ResolvedAircraftObservation(
            observation: observation,
            motion: motion,
        )

        #expect(resolved.observation == observation)
        #expect(resolved.motion == motion)
    }

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
        let expectedOrientation = try Bearing(degrees: 90)

        #expect(motion.horizontalSource == nil)
        #expect(motion.horizontal == .unavailable(orientation: expectedOrientation))
        #expect(motion.groundTrack?.degrees == 90)
        #expect(motion.groundSpeedKnots == nil)
    }

    @Test func turnRateMustStayInsideThePredictionBoundary() {
        #expect(throws: ThrowValidationError.self) {
            try AvailableAircraftHorizontalMotion(
                track: Bearing(degrees: 90),
                speedKnots: 360,
                turnRateDegreesPerSecond: 3.1,
                source: .provider,
            )
        }
    }
}
