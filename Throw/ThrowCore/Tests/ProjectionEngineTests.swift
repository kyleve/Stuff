import Foundation
import Testing
@testable import ThrowCore

struct ProjectionEngineTests {
    private let engine = ProjectionEngine()

    @Test func greatCircleUsesShortAntimeridianPath() throws {
        let origin = try GeoCoordinate(latitude: 0, longitude: 179.9)
        let destination = try GeoCoordinate(latitude: 0, longitude: -179.9)
        let position = try engine.greatCirclePosition(from: origin, to: destination)
        #expect(position.distance.value < 13)
        #expect(abs(position.initialBearing.degrees - 90) < 0.001)
    }

    @Test func polarBearingAndDistanceRemainFinite() throws {
        let origin = try GeoCoordinate(latitude: 89.9, longitude: 0)
        let destination = try GeoCoordinate(latitude: 89.9, longitude: 120)
        let position = try engine.greatCirclePosition(from: origin, to: destination)
        #expect(position.distance.value.isFinite)
        #expect(position.initialBearing.degrees.isFinite)
    }

    @Test func antipodalDistanceDoesNotHitQueryRadiusValidation() throws {
        let origin = try GeoCoordinate(latitude: 0, longitude: 0)
        let destination = try GeoCoordinate(latitude: 0, longitude: 180)
        let position = try engine.greatCirclePosition(from: origin, to: destination)
        #expect(position.distance.value > 10000)
        #expect(position.distance.value < 11000)
    }

    @Test func overheadTargetIsAtZenith() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let target = try GeodeticAnchor(
            coordinate: observer.coordinate,
            altitude: Altitude(feet: 10000),
            altitudeQuality: .geometric,
        )
        let position = try engine.horizontalPosition(observer: observer, target: target)
        let horizontal = try #require(position)
        #expect(abs(horizontal.elevation.degrees - 90) < 0.000_001)
    }

    @Test func earthCurvaturePutsEqualAltitudeDistantTargetBelowHorizon() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let target = try GeodeticAnchor(
            coordinate: GeoCoordinate(latitude: 0, longitude: 1),
            altitude: Altitude(feet: 0),
            altitudeQuality: .geometric,
        )
        let position = try engine.horizontalPosition(observer: observer, target: target)
        let horizontal = try #require(position)
        #expect(horizontal.elevation.degrees < 0)
    }

    @Test func mapPlacesNorthAtCalibratedTopAndEastAtRight() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let frame = try LayerFrame(
            layerID: .flights,
            observedAt: ThrowCoreFixture.date,
            content: .marks([
                mark(rawID: "north", latitude: 0.1, longitude: 0),
                mark(rawID: "east", latitude: 0, longitude: 0.1),
            ]),
        )
        let projection = try engine.frame(
            layerFrames: [frame],
            geography: nil,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1920, height: 1080),
            generatedAt: ThrowCoreFixture.date,
        )
        let north = try #require(projection.marks.first { $0.id.rawValue == "north" })
        let east = try #require(projection.marks.first { $0.id.rawValue == "east" })
        let northRange = try #require(north.range)
        let eastRange = try #require(east.range)
        #expect(north.point.y < 0.5)
        #expect(abs(north.point.x - 0.5) < 0.000_001)
        #expect(abs(northRange.value - 6.004) < 0.01)
        #expect(east.point.x > 0.5)
        #expect(abs(east.point.y - 0.5) < 0.000_001)
        #expect(abs(eastRange.value - 6.004) < 0.01)
    }

    @Test func ninetyDegreeRotationMovesNorthToRight() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let calibration = try ProjectionCalibration(
            screenTopBearing: Bearing(degrees: 0),
            rotation: .degrees90,
            flipHorizontal: false,
            flipVertical: false,
            safeInsetFraction: 0,
            verifiedOnExternalDisplay: true,
        )
        let projection = try engine.frame(
            layerFrames: [
                LayerFrame(
                    layerID: .flights,
                    observedAt: ThrowCoreFixture.date,
                    content: .marks([mark(rawID: "north", latitude: 0.1, longitude: 0)]),
                ),
            ],
            geography: nil,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: calibration,
            geometry: ProjectionGeometry(width: 1000, height: 1000),
            generatedAt: ThrowCoreFixture.date,
        )
        let point = try #require(projection.marks.first).point
        #expect(point.x > 0.5)
        #expect(abs(point.y - 0.5) < 0.000_001)
    }

    @Test func trueSkyClipsBelowMinimumElevation() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let frame = try LayerFrame(
            layerID: .flights,
            observedAt: ThrowCoreFixture.date,
            content: .marks([
                mark(rawID: "low", latitude: 0, longitude: 1, altitudeFeet: 1000),
            ]),
        )
        let projection = try engine.frame(
            layerFrames: [frame],
            geography: nil,
            observer: observer,
            viewport: .trueSky(
                SkyViewport(minimumElevation: ElevationAngle(degrees: 10)),
            ),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1000, height: 1000),
            generatedAt: ThrowCoreFixture.date,
        )
        #expect(projection.marks.isEmpty)
    }

    @Test func trueSkyCarriesSlantRangeIntoProjectedMark() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let frame = try LayerFrame(
            layerID: .flights,
            observedAt: ThrowCoreFixture.date,
            content: .marks([
                mark(rawID: "overhead", latitude: 0, longitude: 0, altitudeFeet: 10000),
            ]),
        )
        let projection = try engine.frame(
            layerFrames: [frame],
            geography: nil,
            observer: observer,
            viewport: .trueSky(
                SkyViewport(minimumElevation: ElevationAngle(degrees: 10)),
            ),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1000, height: 1000),
            generatedAt: ThrowCoreFixture.date,
        )

        let range = try #require(projection.marks.first?.range)
        #expect(abs(range.value - 1.645_79) < 0.000_1)
    }

    @Test func apparentOrientationPredictsFromTheOriginalObservationOnce() throws {
        let generatedAt = Date(timeIntervalSince1970: 1000)
        let observedAt = generatedAt.addingTimeInterval(-12)
        let observer = try ThrowCoreFixture.observer(
            latitude: 80,
            longitude: 0,
            altitudeFeet: 0,
        )
        let movingMark = try ProjectionMark(
            id: LayerMarkID(layerID: .flights, namespace: .aircraft, rawValue: "moving"),
            anchor: .geodetic(GeodeticAnchor(
                coordinate: GeoCoordinate(latitude: 80, longitude: 0.5),
                altitude: Altitude(feet: 30000),
                altitudeQuality: .geometric,
            )),
            glyph: .aircraft(.unknownAirborne),
            label: nil,
            velocity: ProjectionVelocity(
                groundTrack: Bearing(degrees: 35),
                groundSpeedKnots: 2000,
                verticalRateFeetPerMinute: nil,
            ),
            freshness: MarkFreshness(
                positionObservedAt: observedAt,
                fetchedAt: observedAt,
                availability: .current,
            ),
        )
        let viewport = try ProjectionViewport.map(
            MapViewport(radius: NauticalMiles(value: 240)),
        )
        let actualFrame = try engine.frame(
            layerFrames: [LayerFrame(
                layerID: .flights,
                observedAt: observedAt,
                content: .marks([movingMark]),
            )],
            geography: nil,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1000, height: 1000),
            generatedAt: generatedAt,
        )
        let actual = try #require(actualFrame.marks.first?.orientationDegrees)
        let currentPrediction = try FlightPredictor.prediction(
            for: movingMark,
            at: generatedAt,
        )
        let current = try #require(currentPrediction)
        let nextPrediction = try FlightPredictor.prediction(
            for: movingMark,
            at: generatedAt.addingTimeInterval(1),
        )
        let next = try #require(nextPrediction)
        let expectedFrame = try engine.frame(
            layerFrames: [LayerFrame(
                layerID: .flights,
                observedAt: generatedAt,
                content: .marks([
                    positionMark(id: "current", anchor: current.mark.anchor, at: generatedAt),
                    positionMark(id: "next", anchor: next.mark.anchor, at: generatedAt),
                ]),
            )],
            geography: nil,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1000, height: 1000),
            generatedAt: generatedAt,
        )
        let currentPoint = try #require(
            expectedFrame.marks.first(where: { $0.id.rawValue == "current" })?.point,
        )
        let nextPoint = try #require(
            expectedFrame.marks.first(where: { $0.id.rawValue == "next" })?.point,
        )
        let expected = try Bearing(degrees: atan2(
            nextPoint.x - currentPoint.x,
            -(nextPoint.y - currentPoint.y),
        ) * 180 / .pi).degrees

        #expect(angularDifference(actual, expected) < 0.000_001)
    }

    @Test func apparentOrientationPersistsAfterPredictionStops() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let velocity = try ProjectionVelocity(
            groundTrack: Bearing(degrees: 90),
            groundSpeedKnots: 360,
            verticalRateFeetPerMinute: nil,
        )
        let movingMark = try mark(
            rawID: "moving",
            latitude: 0.1,
            longitude: 0,
            velocity: velocity,
        )
        let layerFrame = LayerFrame(
            layerID: .flights,
            observedAt: ThrowCoreFixture.date,
            content: .marks([movingMark]),
        )
        let viewport = try ProjectionViewport.map(
            MapViewport(radius: NauticalMiles(value: 50)),
        )
        let geometry = try ProjectionGeometry(width: 1000, height: 1000)
        let atPredictionLimit = try engine.frame(
            layerFrames: [layerFrame],
            geography: nil,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            geometry: geometry,
            generatedAt: ThrowCoreFixture.date.addingTimeInterval(15),
        )
        let fiveMinutesLater = try engine.frame(
            layerFrames: [layerFrame],
            geography: nil,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            geometry: geometry,
            generatedAt: ThrowCoreFixture.date.addingTimeInterval(300),
        )
        let expected = try #require(atPredictionLimit.marks.first?.orientationDegrees)
        let actual = try #require(fiveMinutesLater.marks.first?.orientationDegrees)

        #expect(angularDifference(actual, expected) < 0.000_001)
        #expect(angularDifference(actual, 90) < 0.1)
    }

    @Test func extremeVerticalPredictionDoesNotDropNeighboringMarks() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let extremeVelocity = try ProjectionVelocity(
            groundTrack: nil,
            groundSpeedKnots: nil,
            verticalRateFeetPerMinute: .greatestFiniteMagnitude,
        )
        let frame = try engine.frame(
            layerFrames: [
                LayerFrame(
                    layerID: .flights,
                    observedAt: ThrowCoreFixture.date,
                    content: .marks([
                        mark(
                            rawID: "extreme",
                            latitude: 0.1,
                            longitude: 0,
                            velocity: extremeVelocity,
                        ),
                        mark(rawID: "neighbor", latitude: 0, longitude: 0.1),
                    ]),
                ),
            ],
            geography: nil,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1000, height: 1000),
            generatedAt: ThrowCoreFixture.date.addingTimeInterval(15),
        )

        #expect(Set(frame.marks.map(\.id.rawValue)) == Set(["extreme", "neighbor"]))
    }

    @Test func verticalOnlyTrueSkyMotionProducesApparentOrientation() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let verticalVelocity = try ProjectionVelocity(
            groundTrack: nil,
            groundSpeedKnots: nil,
            verticalRateFeetPerMinute: 600,
        )
        let frame = try engine.frame(
            layerFrames: [
                LayerFrame(
                    layerID: .flights,
                    observedAt: ThrowCoreFixture.date,
                    content: .marks([
                        mark(
                            rawID: "vertical",
                            latitude: 0,
                            longitude: 0.05,
                            velocity: verticalVelocity,
                        ),
                    ]),
                ),
            ],
            geography: nil,
            observer: observer,
            viewport: .trueSky(
                SkyViewport(minimumElevation: ElevationAngle(degrees: 0)),
            ),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1000, height: 1000),
            generatedAt: ThrowCoreFixture.date,
        )

        #expect(frame.marks.first?.orientationDegrees != nil)
    }

    @Test func geographyClipsAThroughLineWithBothEndpointsOutsideTheMap() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let line = try geographicLine(
            kind: .coastline,
            detailLevel: .wide,
            coordinates: [
                GeoCoordinate(latitude: 0, longitude: -1),
                GeoCoordinate(latitude: 0, longitude: 1),
            ],
        )

        let segments = try engine.geographySegments(
            lines: [line],
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1, height: 1),
        )

        let segment = try #require(segments.first)
        #expect(segments.count == 1)
        #expect(abs(segment.start.x - 0.05) < 0.000_001)
        #expect(abs(segment.end.x - 0.95) < 0.000_001)
        #expect(abs(segment.start.y - 0.5) < 0.000_001)
        #expect(abs(segment.end.y - 0.5) < 0.000_001)
    }

    @Test func geographyPreservesConnectedSubpathsAndRestartsAfterAClippedGap() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let connected = try geographicLine(
            kind: .coastline,
            detailLevel: .wide,
            coordinates: [
                GeoCoordinate(latitude: 0, longitude: 0),
                GeoCoordinate(latitude: 0, longitude: 0.1),
                GeoCoordinate(latitude: 0.1, longitude: 0.1),
            ],
        )
        let clippedGap = try geographicLine(
            kind: .river,
            detailLevel: .wide,
            coordinates: [
                GeoCoordinate(latitude: 0, longitude: 0),
                GeoCoordinate(latitude: 0, longitude: 2),
                GeoCoordinate(latitude: 0, longitude: 3),
                GeoCoordinate(latitude: 0.1, longitude: 0),
            ],
        )

        let segments = try engine.geographySegments(
            lines: [connected, clippedGap],
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1, height: 1),
        )

        let coastlineSegments = segments.filter { $0.kind == .coastline }
        let riverSegments = segments.filter { $0.kind == .river }
        #expect(coastlineSegments.map(\.startsNewSubpath) == [true, false])
        #expect(riverSegments.map(\.startsNewSubpath) == [true, true])
    }

    @Test func geographyIsNeverProjectedIntoTrueSky() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let line = try geographicLine(
            kind: .river,
            detailLevel: .wide,
            coordinates: [
                GeoCoordinate(latitude: 0, longitude: 0),
                GeoCoordinate(latitude: 0.1, longitude: 0),
            ],
        )

        let segments = try engine.geographySegments(
            lines: [line],
            observer: observer,
            viewport: .trueSky(
                SkyViewport(minimumElevation: ElevationAngle(degrees: 10)),
            ),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1, height: 1),
        )

        #expect(segments.isEmpty)
    }

    @Test func localGeographyAppearsOnlyWhenTheMapZoomsIn() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let line = try geographicLine(
            kind: .regionalBoundary,
            detailLevel: .local,
            coordinates: [
                GeoCoordinate(latitude: 0, longitude: 0),
                GeoCoordinate(latitude: 0.01, longitude: 0),
            ],
        )
        let geometry = try ProjectionGeometry(width: 1, height: 1)

        let wide = try engine.geographySegments(
            lines: [line],
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 240))),
            calibration: .defaultValue,
            geometry: geometry,
        )
        let close = try engine.geographySegments(
            lines: [line],
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 5))),
            calibration: .defaultValue,
            geometry: geometry,
        )

        #expect(wide.isEmpty)
        #expect(close.isEmpty == false)
    }

    @Test func standardGeographyIsRemovedFromWideMaps() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 0, longitude: 0, altitudeFeet: 0)
        let line = try geographicLine(
            kind: .river,
            detailLevel: .standard,
            coordinates: [
                GeoCoordinate(latitude: 0, longitude: 0),
                GeoCoordinate(latitude: 0.01, longitude: 0),
            ],
        )
        let geometry = try ProjectionGeometry(width: 1, height: 1)

        let wide = try engine.geographySegments(
            lines: [line],
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 240))),
            calibration: .defaultValue,
            geometry: geometry,
        )
        let close = try engine.geographySegments(
            lines: [line],
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            geometry: geometry,
        )

        #expect(wide.isEmpty)
        #expect(close.isEmpty == false)
    }

    @Test func geographyBoundsRemainConservativeNearThePoles() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 85, longitude: 0, altitudeFeet: 0)
        let line = try geographicLine(
            kind: .coastline,
            detailLevel: .wide,
            coordinates: [
                GeoCoordinate(latitude: 86, longitude: 49),
                GeoCoordinate(latitude: 86, longitude: 50),
            ],
        )

        let segments = try engine.geographySegments(
            lines: [line],
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 240))),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1, height: 1),
        )

        #expect(segments.isEmpty == false)
    }

    @Test func geographyBoundsFindNearbyDataAcrossTheAntimeridian() throws {
        let observer = try ThrowCoreFixture.observer(
            latitude: 0,
            longitude: 179.9,
            altitudeFeet: 0,
        )
        let line = try geographicLine(
            kind: .nationalBoundary,
            detailLevel: .wide,
            coordinates: [
                GeoCoordinate(latitude: -0.1, longitude: -180),
                GeoCoordinate(latitude: 0.1, longitude: -180),
            ],
        )

        let segments = try engine.geographySegments(
            lines: [line],
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1, height: 1),
        )

        #expect(segments.isEmpty == false)
    }

    private func positionMark(
        id: String,
        anchor: ProjectionAnchor,
        at date: Date,
    ) -> ProjectionMark {
        ProjectionMark(
            id: LayerMarkID(layerID: .flights, namespace: .aircraft, rawValue: id),
            anchor: anchor,
            glyph: .aircraft(.unknownAirborne),
            label: nil,
            velocity: nil,
            freshness: MarkFreshness(
                positionObservedAt: date,
                fetchedAt: date,
                availability: .current,
            ),
        )
    }

    private func geographicLine(
        kind: GeographyLineKind,
        detailLevel: GeographyDetailLevel,
        coordinates: [GeoCoordinate],
    ) throws -> GeographicPolyline {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        return try GeographicPolyline(
            kind: kind,
            detailLevel: detailLevel,
            bounds: GeographicBounds(
                southLatitude: latitudes.min() ?? 0,
                westLongitude: longitudes.min() ?? 0,
                northLatitude: latitudes.max() ?? 0,
                eastLongitude: longitudes.max() ?? 0,
            ),
            coordinates: coordinates,
        )
    }

    private func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private func mark(
        rawID: String,
        latitude: Double,
        longitude: Double,
        altitudeFeet: Double = 10000,
        velocity: ProjectionVelocity? = nil,
    ) throws -> ProjectionMark {
        try ProjectionMark(
            id: LayerMarkID(layerID: .flights, namespace: .aircraft, rawValue: rawID),
            anchor: .geodetic(
                GeodeticAnchor(
                    coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
                    altitude: Altitude(feet: altitudeFeet),
                    altitudeQuality: .geometric,
                ),
            ),
            glyph: .aircraft(.unknownAirborne),
            label: nil,
            velocity: velocity,
            freshness: MarkFreshness(
                positionObservedAt: ThrowCoreFixture.date,
                fetchedAt: ThrowCoreFixture.date,
                availability: .current,
            ),
        )
    }
}
