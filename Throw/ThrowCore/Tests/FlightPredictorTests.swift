import Foundation
import Testing
@testable import ThrowCore

struct FlightPredictorTests {
    @Test func predictsAlongGroundTrackUntilNextSuccessfulPoll() throws {
        let mark = try movingMark(positionAge: 0)
        let tenSecondPrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(10),
        )
        let fifteenSecondPrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(15),
        )
        let fiveMinutePrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(300),
        )
        let tenSeconds = try #require(tenSecondPrediction)
        let fifteenSeconds = try #require(fifteenSecondPrediction)
        let fiveMinutes = try #require(fiveMinutePrediction)
        let tenCoordinate = try coordinate(tenSeconds.mark)
        let fifteenCoordinate = try coordinate(fifteenSeconds.mark)
        let fiveMinuteCoordinate = try coordinate(fiveMinutes.mark)
        #expect(tenCoordinate.longitude > 0)
        #expect(fifteenCoordinate.longitude > tenCoordinate.longitude)
        #expect(fiveMinuteCoordinate.longitude > fifteenCoordinate.longitude)
        #expect(fiveMinutes.opacity == 1)
    }

    @Test func successfulPollRemainsVisibleAtFiveMinuteCadence() throws {
        let prediction = try FlightPredictor.prediction(
            for: movingMark(positionAge: 0),
            at: ThrowCoreFixture.date.addingTimeInterval(300),
        )
        #expect(prediction?.opacity == 1)
    }

    @Test func rejectsFuturePositionFreshness() throws {
        let prediction = try FlightPredictor.prediction(
            for: movingMark(positionAge: -1),
            at: ThrowCoreFixture.date,
        )
        #expect(prediction == nil)
    }

    @Test func missingVelocityHoldsBetweenSuccessfulPolls() throws {
        let mark = try stationaryMark()
        let optionalPrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(300),
        )
        let prediction = try #require(optionalPrediction)
        #expect(try coordinate(prediction.mark) == GeoCoordinate(latitude: 0, longitude: 0))
        #expect(prediction.opacity == 1)
    }

    @Test func shortLivedTurnRateCurvesPredictionThenContinuesOnFinalTrack() throws {
        let mark = try mark(
            velocity: ProjectionVelocity(
                groundTrack: Bearing(degrees: 90),
                groundSpeedKnots: 360,
                verticalRateFeetPerMinute: nil,
                turnRateDegreesPerSecond: 1,
                horizontalSource: .provider,
            ),
            positionAge: 0,
        )

        let optionalPrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(30),
        )
        let prediction = try #require(optionalPrediction)
        let predicted = try coordinate(prediction.mark)

        #expect(predicted.longitude > 0)
        #expect(predicted.latitude < 0)
    }

    @Test func failedPollHasGracePeriodThenFades() throws {
        let failureStartedAt = ThrowCoreFixture.date.addingTimeInterval(300)
        let mark = try movingMark(
            positionAge: 0,
            availability: .retrying(since: failureStartedAt),
        )

        let duringGrace = try FlightPredictor.prediction(
            for: mark,
            at: failureStartedAt.addingTimeInterval(15),
        )
        let duringFade = try FlightPredictor.prediction(
            for: mark,
            at: failureStartedAt.addingTimeInterval(22.5),
        )
        let expired = try FlightPredictor.prediction(
            for: mark,
            at: failureStartedAt.addingTimeInterval(30),
        )

        #expect(duringGrace?.opacity == 1)
        #expect(duringFade?.opacity == 0.5)
        #expect(expired == nil)
    }

    @Test func verticalRatePredictsAltitudeWithoutHorizontalVelocity() throws {
        let mark = try mark(
            velocity: ProjectionVelocity(
                groundTrack: nil,
                groundSpeedKnots: nil,
                verticalRateFeetPerMinute: 600,
                turnRateDegreesPerSecond: nil,
                horizontalSource: .unavailable,
            ),
            positionAge: 0,
        )
        let optionalPrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(10),
        )
        let prediction = try #require(optionalPrediction)
        guard case let .geodetic(anchor) = prediction.mark.anchor else {
            Issue.record("Expected a geodetic prediction")
            return
        }
        let expectedCoordinate = try GeoCoordinate(latitude: 0, longitude: 0)
        #expect(anchor.coordinate == expectedCoordinate)
        #expect(anchor.altitude?.feet == 10100)
    }

    @Test func extremeVerticalRateStopsAtTheValidAltitudeBoundary() throws {
        let mark = try mark(
            velocity: ProjectionVelocity(
                groundTrack: nil,
                groundSpeedKnots: nil,
                verticalRateFeetPerMinute: .greatestFiniteMagnitude,
                turnRateDegreesPerSecond: nil,
                horizontalSource: .unavailable,
            ),
            positionAge: 0,
        )
        let optionalPrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(15),
        )
        let prediction = try #require(optionalPrediction)
        guard case let .geodetic(anchor) = prediction.mark.anchor else {
            Issue.record("Expected a geodetic prediction")
            return
        }
        #expect(anchor.altitude?.feet == Altitude.allowedFeet.upperBound)
    }

    private func movingMark(
        positionAge: TimeInterval,
        availability: MarkAvailability = .current,
    ) throws -> ProjectionMark {
        try mark(
            velocity: ProjectionVelocity(
                groundTrack: Bearing(degrees: 90),
                groundSpeedKnots: 360,
                verticalRateFeetPerMinute: 600,
                turnRateDegreesPerSecond: nil,
                horizontalSource: .provider,
            ),
            positionAge: positionAge,
            availability: availability,
        )
    }

    private func stationaryMark() throws -> ProjectionMark {
        try mark(velocity: nil, positionAge: 0)
    }

    private func mark(
        velocity: ProjectionVelocity?,
        positionAge: TimeInterval,
        availability: MarkAvailability = .current,
    ) throws -> ProjectionMark {
        try ProjectionMark(
            id: #require(AircraftID(kind: .icao, rawValue: "a")).layerMarkID,
            anchor: .geodetic(
                GeodeticAnchor(
                    coordinate: GeoCoordinate(latitude: 0, longitude: 0),
                    altitude: Altitude(feet: 10000),
                    altitudeQuality: .geometric,
                ),
            ),
            glyph: .aircraft(.unknownAirborne),
            label: nil,
            prominence: .primary,
            velocity: velocity,
            freshness: MarkFreshness(
                positionObservedAt: ThrowCoreFixture.date.addingTimeInterval(-positionAge),
                fetchedAt: ThrowCoreFixture.date,
                availability: availability,
            ),
        )
    }

    private func coordinate(_ mark: ProjectionMark) throws -> GeoCoordinate {
        guard case let .geodetic(anchor) = mark.anchor else {
            throw TestError.expectedGeodetic
        }
        return anchor.coordinate
    }

    private enum TestError: Error {
        case expectedGeodetic
    }
}
