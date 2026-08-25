import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct ProjectionFrameWorkerTests {
    @Test func modeMorphStartsWithSourceLabelsVisible() async throws {
        let frame = try await modeMorphFrame(progress: 0, reduceMotion: false)
        let mark = try #require(frame.marks.first)

        #expect(mark.label?.primary == "SOURCE")
        #expect(abs(mark.labelOpacity - 1) < 0.000_001)
    }

    @Test func modeMorphMidpointReplacesLabelsWhileTheyAreHidden() async throws {
        let frame = try await modeMorphFrame(progress: 0.5, reduceMotion: false)
        let mark = try #require(frame.marks.first)

        #expect(mark.label?.primary == "TARGET")
        #expect(mark.labelOpacity < 0.000_001)
    }

    @Test func modeMorphEndsWithTargetLabelsVisible() async throws {
        let frame = try await modeMorphFrame(progress: 1, reduceMotion: false)
        let mark = try #require(frame.marks.first)

        #expect(mark.label?.primary == "TARGET")
        #expect(abs(mark.labelOpacity - 1) < 0.000_001)
    }

    @Test func reduceMotionStillFadesTheWholeFrameThroughBlack() async throws {
        let frame = try await modeMorphFrame(progress: 0.5, reduceMotion: true)
        let mark = try #require(frame.marks.first)

        #expect(mark.label?.primary == "TARGET")
        #expect(mark.opacity < 0.000_001)
        #expect(abs(mark.labelOpacity - 1) < 0.000_001)
    }

    @Test func feedCorrectionStartsAtThePreviousDisplayedPosition() async throws {
        let frames = try await correctionFrames(progress: 0, reduceMotion: false)
        let source = try #require(frames.source.marks.first)
        let displayed = try #require(frames.displayed.marks.first)
        let target = try #require(frames.target.marks.first)

        #expect(pointDistance(displayed.point, source.point) < 0.000_001)
        #expect(pointDistance(displayed.point, target.point) > 0.000_1)
    }

    @Test func feedCorrectionMidpointBlendsTheCapturedSourceTowardThePredictedTarget() async throws {
        let frames = try await correctionFrames(progress: 0.5, reduceMotion: false)
        let source = try #require(frames.source.marks.first)
        let displayed = try #require(frames.displayed.marks.first)
        let target = try #require(frames.target.marks.first)
        let expected = ProjectionPoint(
            x: source.point.x + (target.point.x - source.point.x) * 0.5,
            y: source.point.y + (target.point.y - source.point.y) * 0.5,
        )

        #expect(pointDistance(displayed.point, expected) < 0.000_001)
    }

    @Test func feedCorrectionEndsExactlyAtThePredictedTarget() async throws {
        let frames = try await correctionFrames(progress: 1, reduceMotion: false)
        let displayed = try #require(frames.displayed.marks.first)
        let target = try #require(frames.target.marks.first)

        #expect(pointDistance(displayed.point, target.point) < 0.000_001)
    }

    @Test func reduceMotionAppliesFeedCorrectionImmediately() async throws {
        let frames = try await correctionFrames(progress: 0, reduceMotion: true)
        let displayed = try #require(frames.displayed.marks.first)
        let target = try #require(frames.target.marks.first)

        #expect(pointDistance(displayed.point, target.point) < 0.000_001)
    }

    @Test func resetPreventsCorrectionEasingAcrossSourcesWithMatchingIDs() async throws {
        let date = Date(timeIntervalSince1970: 3000)
        let observer = try observer()
        let radius = try NauticalMiles(value: 50)
        let viewport = try ProjectionViewport.map(MapViewport(radius: radius))
        let source = try layerFrame(label: "SOURCE", observedAt: date, observer: observer)
        let replacement = try correctionLayerFrame(
            observedAt: date.addingTimeInterval(1),
            observer: observer,
        )
        let worker = projectionFrameWorker()
        _ = try await worker.frame(
            layerFrame: source,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        )

        await worker.reset()
        let resetFrame = try await worker.frame(
            layerFrame: replacement,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(1),
            reduceMotion: false,
        )
        let freshWorker = projectionFrameWorker()
        let freshFrame = try await freshWorker.frame(
            layerFrame: replacement,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(1),
            reduceMotion: false,
        )

        let resetMark = try #require(resetFrame.marks.first)
        let freshMark = try #require(freshFrame.marks.first)
        #expect(pointDistance(resetMark.point, freshMark.point) < 0.000_001)
    }

    private func modeMorphFrame(
        progress: Double,
        reduceMotion: Bool,
    ) async throws -> ProjectionFrame {
        let date = Date(timeIntervalSince1970: 1000)
        let transitionStartedAt = date.addingTimeInterval(1)
        let worker = projectionFrameWorker()
        let observer = try observer()
        let source = try layerFrame(label: "SOURCE", observedAt: date, observer: observer)
        let target = try layerFrame(
            label: "TARGET",
            observedAt: transitionStartedAt,
            observer: observer,
        )

        _ = try await worker.frame(
            layerFrame: source,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: reduceMotion,
        )
        _ = try await worker.frame(
            layerFrame: target,
            observer: observer,
            viewport: .trueSky(
                SkyViewport(minimumElevation: ElevationAngle(degrees: 10)),
            ),
            calibration: .defaultValue,
            generatedAt: transitionStartedAt,
            reduceMotion: reduceMotion,
        )
        return try await worker.frame(
            layerFrame: target,
            observer: observer,
            viewport: .trueSky(
                SkyViewport(minimumElevation: ElevationAngle(degrees: 10)),
            ),
            calibration: .defaultValue,
            generatedAt: transitionStartedAt.addingTimeInterval(1.2 * progress),
            reduceMotion: reduceMotion,
        )
    }

    private func correctionFrames(
        progress: Double,
        reduceMotion: Bool,
    ) async throws -> (
        source: ProjectionFrame,
        displayed: ProjectionFrame,
        target: ProjectionFrame
    ) {
        let date = Date(timeIntervalSince1970: 2000)
        let frameInterval = 1.0 / 30.0
        let transitionDuration = 0.75
        let correctionStartedAt = date.addingTimeInterval(frameInterval)
        let sampledElapsed = transitionDuration * progress
        let sampledAt = correctionStartedAt.addingTimeInterval(sampledElapsed)
        let worker = projectionFrameWorker()
        let observer = try observer()
        let radius = try NauticalMiles(value: 50)
        let viewport = try ProjectionViewport.map(MapViewport(radius: radius))
        let sourceLayer = try layerFrame(
            label: "SOURCE",
            observedAt: date,
            observer: observer,
        )
        let targetLayer = try correctionLayerFrame(
            observedAt: correctionStartedAt,
            observer: observer,
        )
        let source = try await worker.frame(
            layerFrame: sourceLayer,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: reduceMotion,
        )
        _ = try await worker.frame(
            layerFrame: targetLayer,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: correctionStartedAt,
            reduceMotion: reduceMotion,
        )
        var intermediateElapsed = frameInterval
        while intermediateElapsed < sampledElapsed {
            _ = try await worker.frame(
                layerFrame: targetLayer,
                observer: observer,
                viewport: viewport,
                calibration: .defaultValue,
                generatedAt: correctionStartedAt.addingTimeInterval(intermediateElapsed),
                reduceMotion: reduceMotion,
            )
            intermediateElapsed += frameInterval
        }
        let displayed = try await worker.frame(
            layerFrame: targetLayer,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: sampledAt,
            reduceMotion: reduceMotion,
        )
        let target = try ProjectionEngine().frame(
            layerFrames: [targetLayer],
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1, height: 1),
            generatedAt: sampledAt,
        )
        return (source, displayed, target)
    }

    private func projectionFrameWorker() -> ProjectionFrameWorker {
        ProjectionFrameWorker(
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
        )
    }

    private func observer() throws -> ObserverPosition {
        try ObserverPosition(
            coordinate: GeoCoordinate(latitude: 37, longitude: -122),
            altitude: Altitude(feet: 0),
        )
    }

    private func layerFrame(
        label: String,
        observedAt: Date,
        observer: ObserverPosition,
    ) throws -> LayerFrame {
        try LayerFrame(
            layerID: .flights,
            observedAt: observedAt,
            marks: [
                ProjectionMark(
                    id: LayerMarkID(
                        layerID: .flights,
                        namespace: .aircraft,
                        rawValue: "matching-aircraft",
                    ),
                    anchor: .geodetic(GeodeticAnchor(
                        coordinate: observer.coordinate,
                        altitude: Altitude(feet: 10000),
                        altitudeQuality: .geometric,
                    )),
                    glyph: .aircraft(isGrounded: false),
                    label: ProjectionLabel(primary: label, secondary: nil),
                    velocity: nil,
                    freshness: MarkFreshness(
                        positionObservedAt: observedAt,
                        fetchedAt: observedAt,
                    ),
                ),
            ],
        )
    }

    private func correctionLayerFrame(
        observedAt: Date,
        observer: ObserverPosition,
    ) throws -> LayerFrame {
        try LayerFrame(
            layerID: .flights,
            observedAt: observedAt,
            marks: [
                ProjectionMark(
                    id: LayerMarkID(
                        layerID: .flights,
                        namespace: .aircraft,
                        rawValue: "matching-aircraft",
                    ),
                    anchor: .geodetic(GeodeticAnchor(
                        coordinate: GeoCoordinate(
                            latitude: observer.coordinate.latitude,
                            longitude: observer.coordinate.longitude + 0.02,
                        ),
                        altitude: Altitude(feet: 10000),
                        altitudeQuality: .geometric,
                    )),
                    glyph: .aircraft(isGrounded: false),
                    label: ProjectionLabel(primary: "TARGET", secondary: nil),
                    velocity: ProjectionVelocity(
                        groundTrack: Bearing(degrees: 90),
                        groundSpeedKnots: 600,
                        verticalRateFeetPerMinute: nil,
                    ),
                    freshness: MarkFreshness(
                        positionObservedAt: observedAt,
                        fetchedAt: observedAt,
                    ),
                ),
            ],
        )
    }

    private func pointDistance(_ lhs: ProjectionPoint, _ rhs: ProjectionPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
