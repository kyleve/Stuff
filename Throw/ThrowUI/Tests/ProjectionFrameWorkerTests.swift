import Foundation
import Synchronization
import Testing
@_spi(Testing) import ThrowCore
@testable import ThrowUI

struct ProjectionFrameWorkerTests {
    @Test func duplicateSemanticMarksStayUniqueAcrossAnimationFrames() async throws {
        let date = Date(timeIntervalSince1970: 1000)
        let observer = try observer()
        let first = try layerFrame(label: "FIRST", observedAt: date, observer: observer)
        let replacement = try layerFrame(
            label: "REPLACEMENT",
            observedAt: date,
            observer: observer,
        )
        let layer = LayerFrame(
            layerID: .flights,
            observedAt: date,
            content: .marks(first.marks + replacement.marks),
        )
        let worker = projectionFrameWorker()
        let viewport = try ProjectionViewport.map(
            MapViewport(radius: NauticalMiles(value: 50)),
        )

        let firstFrame = try await worker.frame(
            layerFrame: layer,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        ).frame
        let secondFrame = try await worker.frame(
            layerFrame: layer,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(1.0 / 30.0),
            reduceMotion: false,
        ).frame

        #expect(firstFrame.marks.count == 1)
        #expect(secondFrame.marks.count == 1)
        #expect(secondFrame.marks.first?.label?.primary == "REPLACEMENT")
    }

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

    @Test func feedCorrectionMidpointDecaysHalfTheResidualToThePredictedTarget() async throws {
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

    @Test func feedCorrectionPreservesThePrePollProjectedVelocity() async throws {
        let date = Date(timeIntervalSince1970: 2200)
        let frameInterval = 1.0 / 30.0
        let correctionStartedAt = date.addingTimeInterval(frameInterval * 2)
        let sampledAt = correctionStartedAt.addingTimeInterval(frameInterval)
        let observer = try observer()
        let viewport = try ProjectionViewport.map(
            MapViewport(radius: NauticalMiles(value: 50)),
        )
        let oldLayer = try correctionLayerFrame(
            observedAt: date,
            observer: observer,
            longitudeOffset: 0.01,
        )
        let newLayer = try correctionLayerFrame(
            observedAt: correctionStartedAt,
            observer: observer,
            longitudeOffset: 0.04,
        )
        let worker = projectionFrameWorker()
        let first = try await worker.frame(
            layerFrame: oldLayer,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        ).frame
        let second = try await worker.frame(
            layerFrame: oldLayer,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(frameInterval),
            reduceMotion: false,
        ).frame
        _ = try await worker.frame(
            layerFrame: newLayer,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: correctionStartedAt,
            reduceMotion: false,
        )
        let displayed = try await worker.frame(
            layerFrame: newLayer,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: sampledAt,
            reduceMotion: false,
        ).frame
        let targetMarks = try ProjectionEngine().projectedMarksForTesting(
            layerFrames: [newLayer],
            observer: observer,
            mapCenter: observer.coordinate,
            viewport: viewport,
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1, height: 1),
            generatedAt: sampledAt,
        )
        let firstPoint = try #require(first.marks.first?.point)
        let secondPoint = try #require(second.marks.first?.point)
        let displayedPoint = try #require(displayed.marks.first?.point)
        let targetPoint = try #require(targetMarks.first?.point)
        let continuedSource = ProjectionPoint(
            x: secondPoint.x + (secondPoint.x - firstPoint.x),
            y: secondPoint.y + (secondPoint.y - firstPoint.y),
        )
        let progress = frameInterval / 0.75
        let blend = progress * progress * (3 - 2 * progress)
        let expected = ProjectionPoint(
            x: continuedSource.x + (targetPoint.x - continuedSource.x) * blend,
            y: continuedSource.y + (targetPoint.y - continuedSource.y) * blend,
        )
        let stationarySource = ProjectionPoint(
            x: secondPoint.x + (targetPoint.x - secondPoint.x) * blend,
            y: secondPoint.y + (targetPoint.y - secondPoint.y) * blend,
        )

        #expect(pointDistance(displayedPoint, expected) < 0.000_000_1)
        #expect(pointDistance(displayedPoint, stationarySource) > 0.000_001)
    }

    @Test func reduceMotionAppliesFeedCorrectionImmediately() async throws {
        let frames = try await correctionFrames(progress: 0, reduceMotion: true)
        let displayed = try #require(frames.displayed.marks.first)
        let target = try #require(frames.target.marks.first)

        #expect(pointDistance(displayed.point, target.point) < 0.000_001)
    }

    @Test func newAircraftAndItsLabelFadeInOverQuarterSecond() async throws {
        let frames = try await aircraftPresenceFrames(appears: true)
        let start = try #require(frames.start.marks.first)
        let midpoint = try #require(frames.midpoint.marks.first)
        let end = try #require(frames.end.marks.first)

        #expect(start.opacity < 0.000_001)
        #expect(abs(midpoint.opacity - 0.5) < 0.000_001)
        #expect(abs(midpoint.labelOpacity - 1) < 0.000_001)
        #expect(abs(end.opacity - 1) < 0.000_001)
    }

    @Test func removedAircraftAndItsLabelFadeOutOverQuarterSecond() async throws {
        let frames = try await aircraftPresenceFrames(appears: false)
        let start = try #require(frames.start.marks.first)
        let midpoint = try #require(frames.midpoint.marks.first)

        #expect(abs(start.opacity - 1) < 0.000_001)
        #expect(abs(midpoint.opacity - 0.5) < 0.000_001)
        #expect(abs(midpoint.labelOpacity - 1) < 0.000_001)
        #expect(frames.end.marks.isEmpty)
    }

    @Test func aLabelAddedToAnExistingAircraftFadesIn() async throws {
        let frames = try await labelPresenceFrames(sourceLabel: nil, targetLabel: "TARGET")
        let start = try #require(frames.start.marks.first)
        let midpoint = try #require(frames.midpoint.marks.first)
        let end = try #require(frames.end.marks.first)

        #expect(start.label?.primary == "TARGET")
        #expect(start.labelOpacity < 0.000_001)
        #expect(abs(midpoint.labelOpacity - 0.5) < 0.000_001)
        #expect(abs(end.labelOpacity - 1) < 0.000_001)
    }

    @Test func aLabelRemovedFromAnExistingAircraftFadesOut() async throws {
        let frames = try await labelPresenceFrames(sourceLabel: "SOURCE", targetLabel: nil)
        let start = try #require(frames.start.marks.first)
        let midpoint = try #require(frames.midpoint.marks.first)
        let end = try #require(frames.end.marks.first)

        #expect(start.label?.primary == "SOURCE")
        #expect(abs(start.labelOpacity - 1) < 0.000_001)
        #expect(abs(midpoint.labelOpacity - 0.5) < 0.000_001)
        #expect(end.label == nil)
    }

    @Test func routeEnrichmentFadesThroughBlackWithoutANewObservation() async throws {
        let frames = try await labelPresenceFrames(
            sourceLabel: "UA123",
            targetLabel: "JFK→SFO",
        )
        let start = try #require(frames.start.marks.first)
        let midpoint = try #require(frames.midpoint.marks.first)
        let end = try #require(frames.end.marks.first)

        #expect(start.label?.primary == "UA123")
        #expect(abs(start.labelOpacity - 1) < 0.000_001)
        #expect(midpoint.label?.primary == "JFK→SFO")
        #expect(midpoint.labelOpacity < 0.000_001)
        #expect(end.label?.primary == "JFK→SFO")
        #expect(abs(end.labelOpacity - 1) < 0.000_001)
    }

    @Test func unavailableRouteCrossfadesAircraftToSecondaryProminence() async throws {
        let date = Date(timeIntervalSince1970: 2800)
        let changedAt = date.addingTimeInterval(1)
        let observer = try observer()
        let viewport = try ProjectionViewport.map(MapViewport(radius: NauticalMiles(value: 50)))
        let worker = projectionFrameWorker()
        _ = try await worker.frame(
            layerFrame: layerFrame(
                label: "THROW1",
                observedAt: date,
                observer: observer,
                prominence: .primary,
            ),
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        )
        let target = try layerFrame(
            label: "THROW1",
            observedAt: date,
            observer: observer,
            prominence: .secondary,
        )
        let start = try await worker.frame(
            layerFrame: target,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: changedAt,
            reduceMotion: false,
        ).frame
        let midpoint = try await worker.frame(
            layerFrame: target,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: changedAt.addingTimeInterval(0.375),
            reduceMotion: false,
        ).frame
        let end = try await worker.frame(
            layerFrame: target,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: changedAt.addingTimeInterval(0.75),
            reduceMotion: false,
        ).frame

        #expect(try #require(start.marks.first).secondaryProminence == 0)
        #expect(try abs(#require(midpoint.marks.first).secondaryProminence - 0.5) < 0.000_001)
        #expect(try #require(end.marks.first).secondaryProminence == 1)
    }

    @Test(arguments: [true, false])
    func aircraftCrossingTheViewportBoundaryFades(appears: Bool) async throws {
        let frames = try await viewportBoundaryFrames(appears: appears)
        let start = try #require(frames.start.marks.first)
        let midpoint = try #require(frames.midpoint.marks.first)

        if appears {
            #expect(start.opacity < 0.000_001)
            #expect(abs(midpoint.opacity - 0.5) < 0.000_001)
            #expect(try abs(#require(frames.end.marks.first).opacity - 1) < 0.000_001)
        } else {
            #expect(abs(start.opacity - 1) < 0.000_001)
            #expect(abs(midpoint.opacity - 0.5) < 0.000_001)
            #expect(frames.end.marks.isEmpty)
        }
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
            longitudeOffset: 0.02,
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

    @Test func prewarmingAnotherExperienceDoesNotDisturbVisiblePresentationState() async throws {
        let date = Date(timeIntervalSince1970: 3200)
        let observer = try observer()
        let viewport = try ProjectionViewport.map(MapViewport(radius: NauticalMiles(value: 50)))
        let worker = projectionFrameWorker()
        let visible = try layerFrame(label: "VISIBLE", observedAt: date, observer: observer)
        let prewarming = try layerFrame(
            label: "PREWARM",
            observedAt: date.addingTimeInterval(1),
            observer: observer,
        )

        _ = try await worker.frame(
            experienceID: .airAndSpace,
            layerFrames: [visible],
            geographyEnabled: false,
            observer: observer,
            mapCenter: observer.coordinate,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        )
        _ = try await worker.frame(
            experienceID: .transit,
            layerFrames: [prewarming],
            geographyEnabled: false,
            observer: observer,
            mapCenter: observer.coordinate,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(1),
            reduceMotion: false,
        )
        let resumed = try await worker.frame(
            experienceID: .airAndSpace,
            layerFrames: [visible],
            geographyEnabled: false,
            observer: observer,
            mapCenter: observer.coordinate,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(2),
            reduceMotion: false,
        ).frame

        #expect(resumed.experienceID == .airAndSpace)
        #expect(resumed.marks.first?.label?.primary == "VISIBLE")
        #expect(resumed.marks.first?.labelOpacity == 1)
    }

    @Test func acquisitionRingExpandsOnceForASemanticIdentity() async throws {
        let date = Date(timeIntervalSince1970: 3500)
        let worker = projectionFrameWorker()
        let observer = try observer()
        let viewport = try ProjectionViewport.map(MapViewport(radius: NauticalMiles(value: 50)))
        let layer = try layerFrame(label: nil, observedAt: date, observer: observer)
        let markID = try #require(layer.marks.first?.id)

        let start = try await worker.frame(
            layerFrame: layer,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        )
        let midpoint = try await worker.frame(
            layerFrame: layer,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(0.45),
            reduceMotion: false,
        )
        let finished = try await worker.frame(
            layerFrame: layer,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(0.9),
            reduceMotion: false,
        )

        #expect(start.effects[markID]?.acquisitionProgress == 0)
        #expect(abs((midpoint.effects[markID]?.acquisitionProgress ?? 0) - 0.5) < 0.000_001)
        #expect(finished.effects[markID]?.acquisitionProgress == nil)
    }

    @Test func acquisitionRingReplaysOnlyAfterExperienceFeedWasAbsentForOneMinute() async throws {
        let date = Date(timeIntervalSince1970: 3550)
        let worker = projectionFrameWorker()
        let observer = try observer()
        let viewport = try ProjectionViewport.map(MapViewport(radius: NauticalMiles(value: 50)))
        let firstLayer = try layerFrame(label: nil, observedAt: date, observer: observer)
        let markID = try #require(firstLayer.marks.first?.id)
        _ = try await worker.frame(
            layerFrame: firstLayer,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(1),
            reduceMotion: false,
        )

        await worker.experienceBecameInactive(.airAndSpace, at: date.addingTimeInterval(2))
        let shortAbsence = try await worker.frame(
            layerFrame: layerFrame(
                label: nil,
                observedAt: date.addingTimeInterval(40),
                observer: observer,
            ),
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(40),
            reduceMotion: false,
        )
        #expect(shortAbsence.effects[markID]?.acquisitionProgress == nil)

        await worker.experienceBecameInactive(.airAndSpace, at: date.addingTimeInterval(41))
        let longAbsence = try await worker.frame(
            layerFrame: layerFrame(
                label: nil,
                observedAt: date.addingTimeInterval(102),
                observer: observer,
            ),
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(102),
            reduceMotion: false,
        )
        #expect(longAbsence.effects[markID]?.acquisitionProgress == 0)
    }

    @Test func reduceMotionRemovesAcquisitionRingAndScaleMotion() async throws {
        let date = Date(timeIntervalSince1970: 3600)
        let worker = projectionFrameWorker()
        let observer = try observer()
        let layer = try layerFrame(label: nil, observedAt: date, observer: observer)
        let output = try await worker.frame(
            layerFrame: layer,
            geographyEnabled: false,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: true,
        )
        let markID = try #require(layer.marks.first?.id)

        #expect(output.effects[markID]?.acquisitionProgress == nil)
        #expect(output.effects[markID]?.scale == 1)
    }

    @Test func geographyIsMapOnlyAndLoadsItsStaticArchiveOnce() async throws {
        let source = CountingGeographyDataSource()
        let worker = ProjectionFrameWorker(
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
            geographyRuntime: GeographyLayerRuntime(dataSource: source),
            geographyLogger: DiscardingGeographyLogger(),
            motionLogger: DiscardingProjectionMotionLogger(),
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

    @Test func genericLineLayerUsesTypedStyleAndRevisionCache() async throws {
        let worker = projectionFrameWorker()
        let observer = try observer()
        let date = Date(timeIntervalSince1970: 6500)
        let bounds = try GeographicBounds(
            southLatitude: 37,
            westLongitude: -122,
            northLatitude: 37.1,
            eastLongitude: -121.9,
        )
        let line = try ProjectionPolyline(
            styleID: .transitRoute,
            detailLevel: .wide,
            bounds: bounds,
            coordinates: [
                GeoCoordinate(latitude: 37, longitude: -122),
                GeoCoordinate(latitude: 37.1, longitude: -121.9),
            ],
        )
        func layer(at observedAt: Date) -> LayerFrame {
            LayerFrame(
                layerID: .transitNetwork,
                observedAt: observedAt,
                content: .lines([line]),
            )
        }

        let first = try await worker.frame(
            experienceID: .transit,
            layerFrames: [layer(at: date)],
            geographyEnabled: false,
            observer: observer,
            mapCenter: observer.coordinate,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        ).frame
        let cached = try await worker.frame(
            experienceID: .transit,
            layerFrames: [layer(at: date)],
            geographyEnabled: false,
            observer: observer,
            mapCenter: observer.coordinate,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(1),
            reduceMotion: false,
        ).frame
        let revised = try await worker.frame(
            experienceID: .transit,
            layerFrames: [layer(at: date.addingTimeInterval(2))],
            geographyEnabled: false,
            observer: observer,
            mapCenter: observer.coordinate,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            generatedAt: date.addingTimeInterval(2),
            reduceMotion: false,
        ).frame

        let firstLines = try #require(first.layers.first?.lines)
        let cachedLines = try #require(cached.layers.first?.lines)
        let revisedLines = try #require(revised.layers.first?.lines)
        #expect(first.experienceID == .transit)
        #expect(first.layers.map(\.id) == [.transitNetwork])
        #expect(firstLines.segments.first?.styleID == .transitRoute)
        #expect(cachedLines.id == firstLines.id)
        #expect(revisedLines.id != firstLines.id)
    }

    @Test func overlappingFramesShareTheFirstGeographyLoad() async throws {
        let source = SuspendingGeographyDataSource()
        let worker = ProjectionFrameWorker(
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
            geographyRuntime: GeographyLayerRuntime(dataSource: source),
            geographyLogger: DiscardingGeographyLogger(),
            motionLogger: DiscardingProjectionMotionLogger(),
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
            motionLogger: DiscardingProjectionMotionLogger(),
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
            longitudeOffset: 0.02,
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
        let targetMarks = try ProjectionEngine().projectedMarksForTesting(
            layerFrames: [targetLayer],
            observer: observer,
            mapCenter: observer.coordinate,
            viewport: viewport,
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1, height: 1),
            generatedAt: sampledAt,
        )
        let target = ProjectionFrame.testing(
            mode: viewport.mode,
            generatedAt: sampledAt,
            geography: nil,
            geographyOpacity: 1,
            marks: targetMarks,
        )
        return (source, displayed, target)
    }

    private func aircraftPresenceFrames(
        appears: Bool,
    ) async throws -> (start: ProjectionFrame, midpoint: ProjectionFrame, end: ProjectionFrame) {
        let date = Date(timeIntervalSince1970: 2500)
        let changedAt = date.addingTimeInterval(1)
        let observer = try observer()
        let viewport = try ProjectionViewport.map(MapViewport(radius: NauticalMiles(value: 50)))
        let populated = try layerFrame(label: "FLIGHT", observedAt: date, observer: observer)
        let empty = emptyLayerFrame(observedAt: date)
        let worker = projectionFrameWorker()
        _ = try await worker.frame(
            layerFrame: appears ? empty : populated,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        )
        let target = appears
            ? try layerFrame(label: "FLIGHT", observedAt: changedAt, observer: observer)
            : emptyLayerFrame(observedAt: changedAt)

        let start = try await worker.frame(
            layerFrame: target,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: changedAt,
            reduceMotion: false,
        ).frame
        let midpoint = try await worker.frame(
            layerFrame: target,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: changedAt.addingTimeInterval(0.125),
            reduceMotion: false,
        ).frame
        let end = try await worker.frame(
            layerFrame: target,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: changedAt.addingTimeInterval(0.25),
            reduceMotion: false,
        ).frame
        return (start, midpoint, end)
    }

    private func labelPresenceFrames(
        sourceLabel: String?,
        targetLabel: String?,
    ) async throws -> (start: ProjectionFrame, midpoint: ProjectionFrame, end: ProjectionFrame) {
        let date = Date(timeIntervalSince1970: 2750)
        let changedAt = date.addingTimeInterval(1)
        let observer = try observer()
        let viewport = try ProjectionViewport.map(MapViewport(radius: NauticalMiles(value: 50)))
        let worker = projectionFrameWorker()
        _ = try await worker.frame(
            layerFrame: layerFrame(label: sourceLabel, observedAt: date, observer: observer),
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        )
        let target = try layerFrame(
            label: targetLabel,
            observedAt: date,
            observer: observer,
        )
        let start = try await worker.frame(
            layerFrame: target,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: changedAt,
            reduceMotion: false,
        ).frame
        let midpoint = try await worker.frame(
            layerFrame: target,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: changedAt.addingTimeInterval(0.125),
            reduceMotion: false,
        ).frame
        let end = try await worker.frame(
            layerFrame: target,
            geographyEnabled: false,
            observer: observer,
            viewport: viewport,
            calibration: .defaultValue,
            generatedAt: changedAt.addingTimeInterval(0.25),
            reduceMotion: false,
        ).frame
        return (start, midpoint, end)
    }

    private func viewportBoundaryFrames(
        appears: Bool,
    ) async throws -> (start: ProjectionFrame, midpoint: ProjectionFrame, end: ProjectionFrame) {
        let date = Date(timeIntervalSince1970: 2900)
        let changedAt = date.addingTimeInterval(1)
        let observer = try observer()
        let nearViewport = try ProjectionViewport.map(
            MapViewport(radius: NauticalMiles(value: 5)),
        )
        let farViewport = try ProjectionViewport.map(
            MapViewport(radius: NauticalMiles(value: 50)),
        )
        let layer = try layerFrame(
            label: "FLIGHT",
            observedAt: date,
            observer: observer,
            longitudeOffset: 0.25,
        )
        let worker = projectionFrameWorker()
        _ = try await worker.frame(
            layerFrame: layer,
            geographyEnabled: false,
            observer: observer,
            viewport: appears ? nearViewport : farViewport,
            calibration: .defaultValue,
            generatedAt: date,
            reduceMotion: false,
        )

        let targetViewport = appears ? farViewport : nearViewport
        let start = try await worker.frame(
            layerFrame: layer,
            geographyEnabled: false,
            observer: observer,
            viewport: targetViewport,
            calibration: .defaultValue,
            generatedAt: changedAt,
            reduceMotion: false,
        ).frame
        let midpoint = try await worker.frame(
            layerFrame: layer,
            geographyEnabled: false,
            observer: observer,
            viewport: targetViewport,
            calibration: .defaultValue,
            generatedAt: changedAt.addingTimeInterval(0.125),
            reduceMotion: false,
        ).frame
        let end = try await worker.frame(
            layerFrame: layer,
            geographyEnabled: false,
            observer: observer,
            viewport: targetViewport,
            calibration: .defaultValue,
            generatedAt: changedAt.addingTimeInterval(0.25),
            reduceMotion: false,
        ).frame
        return (start, midpoint, end)
    }

    private func projectionFrameWorker() -> ProjectionFrameWorker {
        ProjectionFrameWorker(
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
            geographyRuntime: GeographyLayerRuntime(dataSource: EmptyGeographyDataSource()),
            geographyLogger: DiscardingGeographyLogger(),
            motionLogger: DiscardingProjectionMotionLogger(),
        )
    }

    private func observer() throws -> ObserverPosition {
        try ObserverPosition(
            coordinate: GeoCoordinate(latitude: 37, longitude: -122),
            altitude: Altitude(feet: 0),
        )
    }

    private func layerFrame(
        label: String?,
        observedAt: Date,
        observer: ObserverPosition,
        prominence: ProjectionProminence = .primary,
        longitudeOffset: Double = 0,
    ) throws -> LayerFrame {
        try LayerFrame(
            layerID: .flights,
            observedAt: observedAt,
            content: .marks([
                ProjectionMark(
                    id: #require(
                        AircraftID(kind: .icao, rawValue: "matching-aircraft"),
                    ).layerMarkID,
                    anchor: .geodetic(GeodeticAnchor(
                        coordinate: GeoCoordinate(
                            latitude: observer.coordinate.latitude,
                            longitude: observer.coordinate.longitude + longitudeOffset,
                        ),
                        altitude: .available(Altitude(feet: 10000), quality: .geometric),
                    )),
                    glyph: .aircraft(.unknownAirborne),
                    label: label.map {
                        ProjectionLabel(
                            primary: $0,
                            primaryRole: .headline,
                            secondary: nil,
                        )
                    },
                    prominence: prominence,
                    velocity: nil,
                    freshness: MarkFreshness(
                        positionObservedAt: observedAt,
                        fetchedAt: observedAt,
                        availability: .current,
                    ),
                ),
            ]),
        )
    }

    private func emptyLayerFrame(observedAt: Date) -> LayerFrame {
        LayerFrame(layerID: .flights, observedAt: observedAt, content: .marks([]))
    }

    private func correctionLayerFrame(
        observedAt: Date,
        observer: ObserverPosition,
        longitudeOffset: Double,
    ) throws -> LayerFrame {
        try LayerFrame(
            layerID: .flights,
            observedAt: observedAt,
            content: .marks([
                ProjectionMark(
                    id: #require(
                        AircraftID(kind: .icao, rawValue: "matching-aircraft"),
                    ).layerMarkID,
                    anchor: .geodetic(GeodeticAnchor(
                        coordinate: GeoCoordinate(
                            latitude: observer.coordinate.latitude,
                            longitude: observer.coordinate.longitude + longitudeOffset,
                        ),
                        altitude: .available(Altitude(feet: 10000), quality: .geometric),
                    )),
                    glyph: .aircraft(.unknownAirborne),
                    label: ProjectionLabel(
                        primary: "TARGET",
                        primaryRole: .headline,
                        secondary: nil,
                    ),
                    prominence: .primary,
                    velocity: ProjectionVelocity.available(
                        track: Bearing(degrees: 90),
                        speedKnots: 600,
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
