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
            glyph: .aircraft(isGrounded: false),
            label: nil,
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
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
        let frame = ProjectionFrame(mode: .map, generatedAt: .now, marks: [aircraft, star])
        #expect(frame.visibleAircraftCount == 1)
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
        let label = ProjectionLabel(primary: labelSentinel, secondary: "12,300 ft")
        let mark = ProjectionMark(
            id: markID,
            anchor: anchor,
            glyph: .aircraft(isGrounded: false),
            label: label,
            velocity: nil,
            freshness: MarkFreshness(
                positionObservedAt: ThrowCoreFixture.date,
                fetchedAt: ThrowCoreFixture.date,
            ),
        )
        let layerFrame = LayerFrame(
            layerID: .flights,
            observedAt: ThrowCoreFixture.date,
            marks: [mark],
        )
        let projectedMark = try ProjectedMark(
            id: markID,
            point: ProjectionPoint(x: 0.4, y: 0.6),
            range: NauticalMiles(value: 5),
            glyph: .aircraft(isGrounded: false),
            label: label,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
        let projectionFrame = ProjectionFrame(
            mode: .map,
            generatedAt: ThrowCoreFixture.date,
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
}
