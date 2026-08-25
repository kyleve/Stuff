import Foundation
import Synchronization
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
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        )

        await worker.reset()
        let resetFrame = try await worker.frame(
            layerFrame: replacement,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(1),
            reduceMotion: false,
        ).frame
        let freshWorker = projectionFrameWorker()
        let freshFrame = try await freshWorker.frame(
            layerFrame: replacement,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(1),
            reduceMotion: false,
        ).frame

        let resetMark = try #require(resetFrame.marks.first)
        let freshMark = try #require(freshFrame.marks.first)
        #expect(pointDistance(resetMark.point, freshMark.point) < 0.000_001)
    }

    @Test func geographyIsMapOnlyAndLoadsItsStaticArchiveOnce() async throws {
        let source = CountingGeographyDataSource()
        let worker = ProjectionFrameWorker(
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
            geographyRuntime: GeographyLayerRuntime(dataSource: source),
            geographyLogger: DiscardingGeographyLogger(),
        )
        let observer = try observer()
        let date = Date(timeIntervalSince1970: 5000)
        let flights = try layerFrame(label: "FLIGHT", observedAt: date, observer: observer)

        let firstMap = try await worker.frame(
            layerFrame: flights,
            geographyEnabled: true,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        ).frame
        let secondMap = try await worker.frame(
            layerFrame: flights,
            geographyEnabled: true,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(1.0 / 30.0),
            reduceMotion: false,
        ).frame
        _ = try await worker.frame(
            layerFrame: flights,
            geographyEnabled: true,
            observer: observer,
            viewport: .trueSky(
                SkyViewport(minimumElevation: ElevationAngle(degrees: 10)),
            ),
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(2.0 / 30.0),
            reduceMotion: false,
        )
        let trueSky = try await worker.frame(
            layerFrame: flights,
            geographyEnabled: true,
            observer: observer,
            viewport: .trueSky(
                SkyViewport(minimumElevation: ElevationAngle(degrees: 10)),
            ),
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(1.3),
            reduceMotion: false,
        ).frame
        let loadCount = await source.loadCount

        #expect(firstMap.geographySegments.isEmpty == false)
        #expect(secondMap.geographySegments == firstMap.geographySegments)
        #expect(trueSky.geographySegments.isEmpty)
        #expect(loadCount == 1)
    }

    @Test func disablingGeographyLeavesAircraftProjectionIntact() async throws {
        let worker = projectionFrameWorker()
        let observer = try observer()
        let date = Date(timeIntervalSince1970: 6000)
        let flights = try layerFrame(label: "FLIGHT", observedAt: date, observer: observer)

        let frame = try await worker.frame(
            layerFrame: flights,
            geographyEnabled: false,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        ).frame

        #expect(frame.geographySegments.isEmpty)
        #expect(frame.marks.count == 1)
    }

    @Test func overlappingFramesShareTheFirstGeographyLoad() async throws {
        let source = SuspendingGeographyDataSource()
        let worker = ProjectionFrameWorker(
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
            geographyRuntime: GeographyLayerRuntime(dataSource: source),
            geographyLogger: DiscardingGeographyLogger(),
        )
        let observer = try observer()
        let date = Date(timeIntervalSince1970: 7000)
        let flights = try layerFrame(label: "FLIGHT", observedAt: date, observer: observer)

        let first = Task {
            try await worker.frame(
                layerFrame: flights,
                geographyEnabled: true,
                observer: observer,
                viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
                calibration: .defaultValue,
                generatedAt: date,
                reduceMotion: false,
            )
        }
        await source.waitUntilLoadStarts()
        let second = Task {
            try await worker.frame(
                layerFrame: flights,
                geographyEnabled: true,
                observer: observer,
                viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
                calibration: .defaultValue,
                generatedAt: date.addingTimeInterval(1.0 / 30.0),
                reduceMotion: false,
            )
        }
        await worker.waitUntilGeographyLoadWaiterCount(2)

        first.cancel()
        await worker.waitUntilGeographyLoadWaiterCount(1)
        await #expect(throws: CancellationError.self) {
            try await first.value
        }
        await source.release()

        let output = try await second.value
        let loadCount = await source.loadCount

        #expect(output.frame.geographySegments.isEmpty == false)
        #expect(loadCount == 1)
    }

    @Test func unavailableGeographyDoesNotBlankOrMisreportFlights() async throws {
        let logger = RecordingGeographyLogger()
        let worker = ProjectionFrameWorker(
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
            geographyRuntime: GeographyLayerRuntime(dataSource: FailingGeographyDataSource()),
            geographyLogger: logger,
        )
        let observer = try observer()
        let date = Date(timeIntervalSince1970: 8000)
        let flights = try layerFrame(label: "FLIGHT", observedAt: date, observer: observer)

        let output = try await worker.frame(
            layerFrame: flights,
            geographyEnabled: true,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        )

        #expect(output.frame.marks.count == 1)
        #expect(output.frame.geography == nil)
        #expect(output.geographyHealth == .unavailable)
        #expect(logger.failureCategories() == [.resourceMissing])
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
            geographyEnabled: false,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: reduceMotion,
        )
        _ = try await worker.frame(
            layerFrame: target,
            geographyEnabled: false,
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
            geographyEnabled: false,
            observer: observer,
            viewport: .trueSky(
                SkyViewport(minimumElevation: ElevationAngle(degrees: 10)),
            ),
            calibration: .defaultValue,
            generatedAt: transitionStartedAt.addingTimeInterval(1.2 * progress),
            reduceMotion: reduceMotion,
        ).frame
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
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: reduceMotion,
        ).frame
        _ = try await worker.frame(
            layerFrame: targetLayer,
            geographyEnabled: false,
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
                geographyEnabled: false,
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
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: sampledAt,
            reduceMotion: reduceMotion,
        ).frame
        let target = try ProjectionEngine().frame(
            layerFrames: [targetLayer],
            geography: nil,
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
            geographyRuntime: GeographyLayerRuntime(dataSource: EmptyGeographyDataSource()),
            geographyLogger: DiscardingGeographyLogger(),
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
            content: .marks([
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
                    glyph: .aircraft(.unknownAirborne),
                    label: ProjectionLabel(primary: label, secondary: nil),
                    velocity: nil,
                    freshness: MarkFreshness(
                        positionObservedAt: observedAt,
                        fetchedAt: observedAt,
                    ),
                ),
            ]),
        )
    }

    private func correctionLayerFrame(
        observedAt: Date,
        observer: ObserverPosition,
    ) throws -> LayerFrame {
        try LayerFrame(
            layerID: .flights,
            observedAt: observedAt,
            content: .marks([
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
                    glyph: .aircraft(.unknownAirborne),
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
            ]),
        )
    }

    private func pointDistance(_ lhs: ProjectionPoint, _ rhs: ProjectionPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

private struct FailingGeographyDataSource: GeographyDataSource {
    func data() async throws -> Data {
        throw GeographyDataError.resourceMissing
    }
}

private final class RecordingGeographyLogger: GeographyLogging {
    private let events = Mutex<[GeographyLogEvent]>([])

    func record(_ event: GeographyLogEvent) {
        events.withLock { $0.append(event) }
    }

    func failureCategories() -> [GeographyLogEvent.FailureCategory] {
        events.withLock { $0.map(\.failureCategory) }
    }
}
