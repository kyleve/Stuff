import Foundation
import Testing
@_spi(Testing) import ThrowCore
@testable import ThrowUI

struct ProjectionMotionDiagnosticsAccumulatorTests {
    @Test func reportsOnlyAggregateCadenceMotionAndSnapshotTurnover() throws {
        let start = Date(timeIntervalSince1970: 10000)
        var accumulator = ProjectionMotionDiagnosticsAccumulator()
        var event: ProjectionMotionLogEvent?

        for index in 0 ... 300 {
            let date = start.addingTimeInterval(Double(index) / 30)
            let identity = index < 60 ? "first" : "second"
            let jump = index >= 30 && index < 60 ? 0.05 : 0
            let layer = try layerFrame(rawID: identity, observedAt: start)
            let target = try projectedFrame(
                rawID: identity,
                x: 0.4 + Double(index) * 0.000_01 + jump,
                at: date,
            )
            event = accumulator.record(
                layerFrame: layer,
                target: target,
                at: date,
                observationChanged: index == 0 || index == 30 || index == 60,
            ) ?? event
        }

        let sample = try #require(event)
        #expect(abs(sample.framesPerSecond - 30) < 0.01)
        #expect(sample.aircraftCount == 1)
        #expect(sample.usableHorizontalMotionPercent == 100)
        #expect(sample.positionDerivedMotionPercent == 0)
        #expect(sample.meanSampleAgeSeconds == 10)
        #expect((sample.meanProjectedSpeedPerSecond ?? 0) > 0)
        #expect((sample.meanCorrectionDistance ?? 0) > 0.04)
        #expect(sample.previousSnapshotRetainedPercent == 0)
    }

    private func layerFrame(
        rawID: String,
        observedAt: Date,
    ) throws -> ProjectionLayerFrame<FlightsLayerKind> {
        let id = try aircraftID(rawValue: rawID)
        return try ProjectionLayerFrame(
            observedAt: observedAt,
            marks: [
                ProjectionMark(
                    element: .aircraft(id: id, glyph: .unknownAirborne),
                    anchor: .geodetic(GeodeticAnchor(
                        coordinate: GeoCoordinate(latitude: 37, longitude: -122),
                        altitude: .available(Altitude(feet: 10000), quality: .geometric),
                    )),
                    label: nil,
                    prominence: .primary,
                    velocity: ProjectionVelocity.available(
                        track: Bearing(degrees: 90),
                        speedKnots: 360,
                        verticalRateFeetPerMinute: nil,
                        turnRateDegreesPerSecond: nil,
                        source: .provider,
                    ),
                    freshness: MarkFreshness(
                        positionObservedAt: observedAt,
                        fetchedAt: observedAt,
                        availability: .current,
                    ),
                ),
            ],
        )
    }

    private func projectedFrame(
        rawID: String,
        x: Double,
        at date: Date,
    ) throws -> ProjectionFrame {
        try ProjectionFrame.testing(
            mode: .map,
            generatedAt: date,
            geography: nil,
            geographyOpacity: 1,
            marks: [PresentedMark(
                id: markID(rawValue: rawID),
                point: ProjectionPoint(x: x, y: 0.5),
                range: NauticalMiles(value: 10),
                glyph: .aircraft(.unknownAirborne),
                label: nil,
                secondaryProminence: 0,
                orientationDegrees: 90,
                opacity: 1,
                labelOpacity: 1,
                altitudeIsApproximate: false,
            )],
        )
    }

    private func markID(rawValue: String) throws -> LayerMarkID {
        try .aircraft(aircraftID(rawValue: rawValue))
    }

    private func aircraftID(rawValue: String) throws -> AircraftID {
        try #require(AircraftID(kind: .icao, rawValue: rawValue))
    }
}
