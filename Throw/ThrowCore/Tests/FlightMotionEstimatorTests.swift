import Foundation
import Testing
@testable import ThrowCore

struct FlightMotionEstimatorTests {
    @Test func consecutivePositionsSupplyMissingHorizontalMotion() throws {
        var estimator = FlightMotionEstimator()
        let first = try observation(longitude: -122.02, positionAge: 10)
        let second = try observation(longitude: -122, positionAge: 0)

        let firstMotions = try estimator.motions(
            for: snapshot(first, fetchedAt: ThrowCoreFixture.date.addingTimeInterval(-10)),
        )
        let secondMotions = try estimator.motions(
            for: snapshot(second, fetchedAt: ThrowCoreFixture.date),
        )
        let firstMotion = try #require(firstMotions[first.id])
        let secondMotion = try #require(secondMotions[second.id])

        #expect(firstMotion.horizontalSource == .unavailable)
        #expect(secondMotion.horizontalSource == .positionDerived)
        #expect(try #require(secondMotion.groundTrack).degrees > 80)
        #expect(try #require(secondMotion.groundTrack).degrees < 100)
        #expect(try #require(secondMotion.groundSpeedKnots) > 300)
        #expect(try #require(secondMotion.groundSpeedKnots) < 500)
    }

    @Test func clearlyContradictoryProviderTrackUsesObservedPositions() throws {
        var estimator = FlightMotionEstimator()
        let first = try ThrowCoreFixture.observation(
            longitude: -122.02,
            positionAge: 10,
            groundSpeedKnots: 360,
            groundTrackDegrees: 90,
        )
        let second = try ThrowCoreFixture.observation(
            longitude: -122,
            positionAge: 0,
            groundSpeedKnots: 360,
            groundTrackDegrees: 270,
        )
        _ = try estimator.motions(
            for: snapshot(first, fetchedAt: ThrowCoreFixture.date.addingTimeInterval(-10)),
        )

        let motions = try estimator.motions(
            for: snapshot(second, fetchedAt: ThrowCoreFixture.date),
        )
        let motion = try #require(motions[second.id])

        #expect(motion.horizontalSource == .positionDerived)
        #expect(try #require(motion.groundTrack).degrees > 80)
        #expect(try #require(motion.groundTrack).degrees < 100)
    }

    @Test func recentConsistentProviderTracksProduceBoundedTurnRate() throws {
        var estimator = FlightMotionEstimator()
        let first = try ThrowCoreFixture.observation(
            longitude: -122.02,
            positionAge: 10,
            groundSpeedKnots: 360,
            groundTrackDegrees: 90,
        )
        let second = try ThrowCoreFixture.observation(
            longitude: -122,
            positionAge: 0,
            groundSpeedKnots: 360,
            groundTrackDegrees: 96,
        )
        _ = try estimator.motions(
            for: snapshot(first, fetchedAt: ThrowCoreFixture.date.addingTimeInterval(-10)),
        )

        let motions = try estimator.motions(
            for: snapshot(second, fetchedAt: ThrowCoreFixture.date),
        )
        let motion = try #require(motions[second.id])

        #expect(motion.horizontalSource == .provider)
        #expect(abs((motion.turnRateDegreesPerSecond ?? 0) - 0.6) < 0.000_001)
    }

    @Test func longPollingIntervalDoesNotTreatAverageCourseAsCurrentTrack() throws {
        var estimator = FlightMotionEstimator()
        let first = try ThrowCoreFixture.observation(
            longitude: -122.5,
            positionAge: 300,
            groundSpeedKnots: 360,
            groundTrackDegrees: 90,
        )
        let second = try ThrowCoreFixture.observation(
            longitude: -122,
            positionAge: 0,
            groundSpeedKnots: 360,
            groundTrackDegrees: 270,
        )
        _ = try estimator.motions(
            for: snapshot(first, fetchedAt: ThrowCoreFixture.date.addingTimeInterval(-300)),
        )

        let motions = try estimator.motions(
            for: snapshot(second, fetchedAt: ThrowCoreFixture.date),
        )
        let motion = try #require(motions[second.id])

        #expect(motion.horizontalSource == .provider)
        #expect(motion.groundTrack?.degrees == 270)
    }

    @Test func routeOnlyRebuildDoesNotConsumeTheSamePositionAgain() throws {
        var estimator = FlightMotionEstimator()
        let first = try observation(longitude: -122.02, positionAge: 10)
        let second = try observation(longitude: -122, positionAge: 0)
        _ = try estimator.motions(
            for: snapshot(first, fetchedAt: ThrowCoreFixture.date.addingTimeInterval(-10)),
        )
        let current = snapshot(second, fetchedAt: ThrowCoreFixture.date)
        let initialMotions = try estimator.motions(for: current)
        let initiallyDerived = try #require(initialMotions[second.id])

        let rebuiltMotions = try estimator.motions(for: current)
        let rebuilt = try #require(rebuiltMotions[second.id])

        #expect(rebuilt == initiallyDerived)
        #expect(rebuilt.horizontalSource == .positionDerived)
    }

    @Test func changingProviderClearsConsecutivePositionHistory() throws {
        var estimator = FlightMotionEstimator()
        let first = try observation(longitude: -122.02, positionAge: 10, source: .adsbLol)
        let second = try observation(longitude: -122, positionAge: 0, source: .readsb)
        _ = try estimator.motions(
            for: snapshot(
                first,
                source: .adsbLol,
                fetchedAt: ThrowCoreFixture.date.addingTimeInterval(-10),
            ),
        )

        let motions = try estimator.motions(
            for: snapshot(second, source: .readsb, fetchedAt: ThrowCoreFixture.date),
        )
        let motion = try #require(motions[second.id])

        #expect(motion.horizontalSource == .unavailable)
    }

    private func observation(
        longitude: Double,
        positionAge: TimeInterval,
        source: AircraftSourceKind = .adsbLol,
    ) throws -> AircraftObservation {
        try ThrowCoreFixture.observation(
            longitude: longitude,
            positionAge: positionAge,
            source: source,
            groundSpeedKnots: nil,
            groundTrackDegrees: nil,
        )
    }

    private func snapshot(
        _ observation: AircraftObservation,
        source: AircraftSourceKind = .adsbLol,
        fetchedAt: Date,
    ) -> AircraftSnapshot {
        AircraftSnapshot(source: source, fetchedAt: fetchedAt, observations: [observation])
    }
}
