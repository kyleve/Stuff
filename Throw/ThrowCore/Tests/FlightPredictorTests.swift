import Foundation
import Testing
@testable import ThrowCore

struct FlightPredictorTests {
    @Test func predictsAlongGroundTrackUntilFifteenSeconds() throws {
        let mark = try movingMark(positionAge: 0)
        let tenSecondPrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(10),
        )
        let fifteenSecondPrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(15),
        )
        let twentySecondPrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(20),
        )
        let tenSeconds = try #require(tenSecondPrediction)
        let fifteenSeconds = try #require(fifteenSecondPrediction)
        let twentySeconds = try #require(twentySecondPrediction)
        let tenCoordinate = try coordinate(tenSeconds.mark)
        let fifteenCoordinate = try coordinate(fifteenSeconds.mark)
        let twentyCoordinate = try coordinate(twentySeconds.mark)
        #expect(tenCoordinate.longitude > 0)
        #expect(fifteenCoordinate.longitude > tenCoordinate.longitude)
        #expect(twentyCoordinate == fifteenCoordinate)
        #expect(abs(twentySeconds.opacity - (2.0 / 3.0)) < 0.000_001)
    }

    @Test func removesAtThirtySeconds() throws {
        let prediction = try FlightPredictor.prediction(
            for: movingMark(positionAge: 0),
            at: ThrowCoreFixture.date.addingTimeInterval(30),
        )
        #expect(prediction == nil)
    }

    @Test func rejectsFuturePositionFreshness() throws {
        let prediction = try FlightPredictor.prediction(
            for: movingMark(positionAge: -1),
            at: ThrowCoreFixture.date,
        )
        #expect(prediction == nil)
    }

    @Test func missingVelocityHoldsThenFades() throws {
        let mark = try stationaryMark()
        let optionalPrediction = try FlightPredictor.prediction(
            for: mark,
            at: ThrowCoreFixture.date.addingTimeInterval(22.5),
        )
        let prediction = try #require(optionalPrediction)
        #expect(try coordinate(prediction.mark) == GeoCoordinate(latitude: 0, longitude: 0))
        #expect(abs(prediction.opacity - 0.5) < 0.000_001)
    }

    @Test func verticalRatePredictsAltitudeWithoutHorizontalVelocity() throws {
        let mark = try mark(
            velocity: ProjectionVelocity(
                groundTrack: nil,
                groundSpeedKnots: nil,
                verticalRateFeetPerMinute: 600,
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

    private func movingMark(positionAge: TimeInterval) throws -> ProjectionMark {
        try mark(
            velocity: ProjectionVelocity(
                groundTrack: Bearing(degrees: 90),
                groundSpeedKnots: 360,
                verticalRateFeetPerMinute: 600,
            ),
            positionAge: positionAge,
        )
    }

    private func stationaryMark() throws -> ProjectionMark {
        try mark(velocity: nil, positionAge: 0)
    }

    private func mark(
        velocity: ProjectionVelocity?,
        positionAge: TimeInterval,
    ) throws -> ProjectionMark {
        try ProjectionMark(
            id: LayerMarkID(layerID: .flights, namespace: .aircraft, rawValue: "a"),
            anchor: .geodetic(
                GeodeticAnchor(
                    coordinate: GeoCoordinate(latitude: 0, longitude: 0),
                    altitude: Altitude(feet: 10000),
                    altitudeQuality: .geometric,
                ),
            ),
            glyph: .aircraft(isGrounded: false),
            label: nil,
            velocity: velocity,
            freshness: MarkFreshness(
                positionObservedAt: ThrowCoreFixture.date.addingTimeInterval(-positionAge),
                fetchedAt: ThrowCoreFixture.date,
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
