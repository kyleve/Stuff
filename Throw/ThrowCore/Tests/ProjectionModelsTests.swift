import Foundation
import Testing
@testable import ThrowCore

struct ProjectionModelsTests {
    @Test func calibrationRejectsInsetAboveTwentyPercent() throws {
        #expect(throws: ThrowValidationError.self) {
            try ProjectionCalibration(
                screenTopBearing: Bearing(degrees: 0),
                rotation: .degrees0,
                flipHorizontal: false,
                flipVertical: false,
                safeInsetFraction: 0.21,
                verifiedOnExternalDisplay: false,
            )
        }
    }

    @Test func markIdentityIncludesLayerAndNamespace() {
        let aircraft = LayerMarkID(
            layerID: .flights,
            namespace: .aircraft,
            rawValue: "same",
        )
        let satellite = LayerMarkID(
            layerID: .satellites,
            namespace: .satellite,
            rawValue: "same",
        )
        #expect(aircraft != satellite)
    }

    @Test func visibleAircraftCountExcludesOtherGlyphs() throws {
        let aircraft = try ProjectedMark(
            id: LayerMarkID(layerID: .flights, namespace: .aircraft, rawValue: "a"),
            point: ProjectionPoint(x: 0.5, y: 0.5),
            range: NauticalMiles(value: 1),
            glyph: .aircraft(.unknownAirborne),
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
        let star = ProjectedMark(
            id: LayerMarkID(layerID: .stars, namespace: .star, rawValue: "s"),
            point: ProjectionPoint(x: 0.5, y: 0.5),
            range: nil,
            glyph: .star,
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
        let frame = ProjectionFrame(
            mode: .map,
            generatedAt: .now,
            geography: nil,
            geographyOpacity: 1,
            marks: [aircraft, star],
        )
        #expect(frame.visibleAircraftCount == 1)
    }

    @Test func lineStyleIdentitySupportsGeographyAndFutureNetworks() {
        let coastline = ProjectionLineStyleID(geographyKind: .coastline)

        #expect(coastline.geographyKind == .coastline)
        #expect(ProjectionLineStyleID.transitRoute.geographyKind == nil)
        #expect(coastline != .transitRoute)
    }

    @Test func projectedFrameOrdersGenericLayersWithinItsExperience() throws {
        let mark = try projectedMark(layerID: .transitVehicles, rawID: "vehicle")
        let lines = ProjectedLineCollection(
            id: ProjectionLineRevisionID(rawValue: 7),
            segments: [ProjectedLineSegment(
                styleID: .transitRoute,
                start: ProjectionPoint(x: 0.1, y: 0.2),
                end: ProjectionPoint(x: 0.8, y: 0.9),
                startsNewSubpath: true,
            )],
        )
        let frame = ProjectionFrame(
            experienceID: .transit,
            mode: .map,
            generatedAt: ThrowCoreFixture.date,
            layers: [
                ProjectedLayer(
                    id: .transitVehicles,
                    zOrder: 40,
                    opacity: 1,
                    content: .marks([mark]),
                ),
                ProjectedLayer(
                    id: .transitNetwork,
                    zOrder: 20,
                    opacity: 0.4,
                    content: .lines(lines),
                ),
            ],
        )

        #expect(frame.experienceID == .transit)
        #expect(frame.layers.map(\.id) == [.transitNetwork, .transitVehicles])
        #expect(frame.layers.first?.lines == lines)
    }

    @Test func replacingMarksPreservesExperienceAndLineLayers() throws {
        let original = try projectedMark(layerID: .transitVehicles, rawID: "old")
        let replacement = try projectedMark(layerID: .transitVehicles, rawID: "new")
        let lines = ProjectedLineCollection(
            id: ProjectionLineRevisionID(rawValue: 9),
            segments: [],
        )
        let frame = ProjectionFrame(
            experienceID: .transit,
            mode: .map,
            generatedAt: ThrowCoreFixture.date,
            layers: [
                ProjectedLayer(
                    id: .transitNetwork,
                    zOrder: 10,
                    opacity: 0.25,
                    content: .lines(lines),
                ),
                ProjectedLayer(
                    id: .transitVehicles,
                    zOrder: 20,
                    opacity: 1,
                    content: .marks([original]),
                ),
            ],
        )

        let replaced = frame.replacingMarks([replacement])

        #expect(replaced.experienceID == .transit)
        #expect(replaced.layers.first?.lines == lines)
        #expect(replaced.marks.map(\.id.rawValue) == ["new"])

        let noLines = frame.replacingLineLayers([])
        #expect(noLines.experienceID == .transit)
        #expect(noLines.layers.map(\.id) == [.transitVehicles])
    }

    @Test func frameDescriptionsRedactMarksLabelsIdentitiesAndCoordinates() throws {
        let markIDSentinel = "mark-id-do-not-leak"
        let labelSentinel = "LABEL-DO-NOT-LEAK"
        let coordinateSentinel = "33.123456"
        let markID = LayerMarkID(
            layerID: .flights,
            namespace: .aircraft,
            rawValue: markIDSentinel,
        )
        let geodeticAnchor = try GeodeticAnchor(
            coordinate: GeoCoordinate(latitude: 33.123456, longitude: -111.654321),
            altitude: Altitude(feet: 12300),
            altitudeQuality: .geometric,
        )
        let anchor = ProjectionAnchor.geodetic(geodeticAnchor)
        let label = ProjectionLabel(
            primary: labelSentinel,
            primaryRole: .headline,
            secondary: "12,300 ft",
        )
        let mark = ProjectionMark(
            id: markID,
            anchor: anchor,
            glyph: .aircraft(.unknownAirborne),
            label: label,
            prominence: .primary,
            velocity: nil,
            freshness: MarkFreshness(
                positionObservedAt: ThrowCoreFixture.date,
                fetchedAt: ThrowCoreFixture.date,
                availability: .current,
            ),
        )
        let layerFrame = LayerFrame(
            layerID: .flights,
            observedAt: ThrowCoreFixture.date,
            content: .marks([mark]),
        )
        let projectedMark = try ProjectedMark(
            id: markID,
            point: ProjectionPoint(x: 0.4, y: 0.6),
            range: NauticalMiles(value: 5),
            glyph: .aircraft(.unknownAirborne),
            label: label,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
        let projectionFrame = ProjectionFrame(
            mode: .map,
            generatedAt: ThrowCoreFixture.date,
            geography: nil,
            geographyOpacity: 1,
            marks: [projectedMark],
        )
        let renderings = [
            String(describing: markID),
            String(reflecting: markID),
            String(describing: geodeticAnchor),
            String(reflecting: geodeticAnchor),
            String(describing: anchor),
            String(reflecting: anchor),
            String(describing: label),
            String(reflecting: label),
            String(describing: mark),
            String(reflecting: mark),
            String(describing: layerFrame),
            String(reflecting: layerFrame),
            String(describing: projectedMark),
            String(reflecting: projectedMark),
            String(describing: projectionFrame),
            String(reflecting: projectionFrame),
        ]

        for rendering in renderings {
            #expect(rendering.contains(markIDSentinel) == false)
            #expect(rendering.contains(labelSentinel) == false)
            #expect(rendering.contains(coordinateSentinel) == false)
        }
    }

    private func projectedMark(layerID: LayerID, rawID: String) throws -> ProjectedMark {
        try ProjectedMark(
            id: LayerMarkID(layerID: layerID, namespace: .aircraft, rawValue: rawID),
            point: ProjectionPoint(x: 0.5, y: 0.5),
            range: NauticalMiles(value: 1),
            glyph: .aircraft(.unknownAirborne),
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
    }
}
