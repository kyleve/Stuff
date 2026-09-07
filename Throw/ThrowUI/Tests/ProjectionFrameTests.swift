import Foundation
import Testing
@_spi(Testing) import ThrowCore
@testable import ThrowUI

struct ProjectionFrameTests {
    @Test func presentationIdentitySeparatesViewsAndDebugFrames() {
        let map = present(.airAndSpace(.map(AirAndSpaceMapProjectedFrame(
            generatedAt: testDate,
            geography: nil,
            flights: nil,
            satellites: nil,
        ))))
        let trueSky = present(.airAndSpace(.trueSky(AirAndSpaceTrueSkyProjectedFrame(
            generatedAt: testDate,
            flights: nil,
            stars: nil,
            satellites: nil,
        ))))
        let transit = present(.transit(TransitProjectedFrame(
            generatedAt: testDate,
            geography: nil,
            network: nil,
            vehicles: nil,
        )))
        let testing = ProjectionFrame.testing(
            experienceID: .airAndSpace,
            mode: .map,
            generatedAt: testDate,
            layers: [],
        )

        #expect(map.hasSamePresentationExperience(as: trueSky))
        #expect(map.hasSamePresentationExperience(as: transit) == false)
        #expect(map.hasSamePresentationExperience(as: testing) == false)
    }

    @Test func transitPresentationErasesOnlyItsFixedLayersInRenderOrder() throws {
        let geography = geographyLineCollection(id: 1, kind: .coastline)
        let network = try transitLineCollection(id: 2)
        let vehicleID = try #require(TransitVehicleID(rawValue: "vehicle"))
        let vehicle = try transitVehicleMark(id: vehicleID)
        let stopID = try TransitStopMarkID(
            stopID: #require(TransitStopID(
                agencyID: .mtaNewYorkCityTransit,
                rawValue: "A01",
            )),
            context: "next-stop",
        )
        let stop = try transitStopMark(id: stopID)
        let frame = present(.transit(TransitProjectedFrame(
            generatedAt: testDate,
            geography: .testing(lines: geography),
            network: .testing(lines: network),
            vehicles: ProjectedLayerFrame(marks: [vehicle, stop]),
        )))

        #expect(frame.experienceID == .transit)
        #expect(frame.mode == .map)
        #expect(frame.layers.map(\.id) == [.geography, .transitNetwork, .transitVehicles])
        #expect(frame.layers.map(\.content) == [
            .geography(geography),
            .transitNetwork(network),
            .transitVehicles([vehicle, stop]),
        ])
        #expect(frame.marks.map(\.id) == [.transitVehicle(vehicleID), .transitStop(stopID)])
    }

    @Test func trueSkyPresentationCannotAcquireGeography() throws {
        let aircraft = try aircraftMark(rawID: "aircraft")
        let star = try starMark(rawID: "star")
        let frame = present(.airAndSpace(.trueSky(AirAndSpaceTrueSkyProjectedFrame(
            generatedAt: testDate,
            flights: ProjectedLayerFrame(marks: [aircraft]),
            stars: ProjectedLayerFrame(marks: [star]),
            satellites: nil,
        ))))

        #expect(frame.experienceID == .airAndSpace)
        #expect(frame.mode == .trueSky)
        #expect(frame.geography == nil)
        #expect(frame.layers.map(\.id) == [.stars, .flights])
        #expect(frame.visibleAircraftCount == 1)
    }

    @Test func markReplacementPreservesTheErasedLineRevisionAndIdentity() throws {
        let geography = geographyLineCollection(id: 7, kind: .coastline)
        let first = try aircraftMark(rawID: "first")
        let replacement = try aircraftMark(rawID: "replacement")
        let frame = present(.airAndSpace(.map(AirAndSpaceMapProjectedFrame(
            generatedAt: testDate,
            geography: .testing(lines: geography),
            flights: ProjectedLayerFrame(marks: [first]),
            satellites: nil,
        ))))

        let replacementFrame = present(.airAndSpace(.map(AirAndSpaceMapProjectedFrame(
            generatedAt: testDate,
            geography: nil,
            flights: ProjectedLayerFrame(marks: [replacement]),
            satellites: nil,
        ))))
        let replacementFields = Dictionary(uniqueKeysWithValues: replacementFrame.marks.map {
            ($0.id, PresentedMarkFields($0))
        })
        let replaced = try #require(frame.updatingMarkPresentation(
            fieldsByID: replacementFields,
            retainedTargetIDs: [],
            appendedSourceIDs: Set(replacementFrame.marks.map(\.id)),
            sourceFrame: replacementFrame,
            lineLayersFrom: frame,
            lineOpacity: 1,
        ))

        #expect(replaced.experienceID == .airAndSpace)
        #expect(replaced.mode == .map)
        #expect(replaced.geography == geography)
        #expect(replaced.marks.map(\.id) == [presentationID(replacement.id)])
        #expect(replaced.description == "<ProjectionFrame mode=map marks=1 geography=1>")
    }

    private var testDate: Date {
        Date(timeIntervalSince1970: 100)
    }

    @Test func productionReplacementRejectsAFrameFromAnotherPresentationCase() throws {
        let aircraft = try aircraftMark(rawID: "aircraft")
        let vehicle = try transitVehicleMark(
            id: #require(TransitVehicleID(rawValue: "vehicle")),
        )
        let frame = present(.airAndSpace(.map(AirAndSpaceMapProjectedFrame(
            generatedAt: testDate,
            geography: nil,
            flights: ProjectedLayerFrame(marks: [aircraft]),
            satellites: nil,
        ))))
        let transit = present(.transit(TransitProjectedFrame(
            generatedAt: testDate,
            geography: nil,
            network: nil,
            vehicles: ProjectedLayerFrame(marks: [vehicle]),
        )))

        let replaced = frame.updatingMarkPresentation(
            fieldsByID: Dictionary(uniqueKeysWithValues: transit.marks.map {
                ($0.id, PresentedMarkFields($0))
            }),
            retainedTargetIDs: Set(frame.marks.map(\.id)),
            appendedSourceIDs: Set(transit.marks.map(\.id)),
            sourceFrame: transit,
            lineLayersFrom: frame,
            lineOpacity: 1,
        )

        #expect(frame.hasSamePresentationCase(as: transit) == false)
        #expect(replaced == nil)
    }

    @Test func mapAndTrueSkyAreDifferentPresentationCases() {
        let map = ProjectionFrame.emptyAirAndSpace(mode: .map, generatedAt: testDate)
        let trueSky = ProjectionFrame.emptyAirAndSpace(mode: .trueSky, generatedAt: testDate)

        #expect(map.hasSamePresentationExperience(as: trueSky))
        #expect(map.hasSamePresentationCase(as: trueSky) == false)
        #expect(map.updatingMarkPresentation(
            fieldsByID: [:],
            retainedTargetIDs: [],
            appendedSourceIDs: [],
            sourceFrame: trueSky,
            lineLayersFrom: map,
            lineOpacity: 1,
        ) == nil)
    }

    private func geographyLineCollection(
        id: UInt64,
        kind: GeographyLineKind,
    ) -> ProjectedGeography {
        ProjectedGeography.testing(
            id: ProjectionLineRevisionID.testing(rawValue: id),
            segments: [ProjectedLineSegment(
                style: kind,
                start: ProjectionPoint(x: 0.1, y: 0.2),
                end: ProjectionPoint(x: 0.8, y: 0.9),
                startsNewSubpath: true,
            )],
        )
    }

    private func transitLineCollection(
        id: UInt64,
    ) throws -> ProjectedLineCollection<TransitNetworkLineStyle> {
        try ProjectedLineCollection.testing(
            id: ProjectionLineRevisionID.testing(rawValue: id),
            segments: [ProjectedLineSegment(
                style: TransitNetworkLineStyle(
                    routeID: #require(TransitRouteID(
                        agencyID: .mtaNewYorkCityTransit,
                        rawValue: "A",
                    )),
                    color: #require(TransitColor(hex: "0039A6")),
                ),
                start: ProjectionPoint(x: 0.1, y: 0.2),
                end: ProjectionPoint(x: 0.8, y: 0.9),
                startsNewSubpath: true,
            )],
        )
    }

    private func aircraftMark(rawID: String) throws -> ProjectedMark<FlightsMarkElement> {
        let id = try #require(AircraftID(kind: .icao, rawValue: rawID))
        return try projectedMark(element: FlightsMarkElement.aircraft(
            id: id,
            glyph: .unknownAirborne,
        ))
    }

    private func starMark(rawID: String) throws -> ProjectedMark<StarMarkElement> {
        try projectedMark(element: StarMarkElement(id: #require(StarID(rawValue: rawID))))
    }

    private func transitVehicleMark(
        id: TransitVehicleID,
    ) throws -> ProjectedMark<TransitVehicleMarkElement> {
        try projectedMark(element: .vehicle(
            id: id,
            descriptor: TransitVehicleGlyphDescriptor(
                routeLabel: "A",
                color: #require(TransitColor(hex: "0039A6")),
                confidence: .feedTracked,
            ),
        ))
    }

    private func transitStopMark(
        id: TransitStopMarkID,
    ) throws -> ProjectedMark<TransitVehicleMarkElement> {
        try projectedMark(element: .stop(
            id: id,
            descriptor: TransitStopGlyphDescriptor(
                color: #require(TransitColor(hex: "0039A6")),
            ),
        ))
    }

    private func projectedMark<Element: ProjectionMarkElement>(
        element: Element,
    ) throws -> ProjectedMark<Element> {
        try ProjectedMark(
            element: element,
            point: ProjectionPoint(x: 0.5, y: 0.5),
            range: NauticalMiles(value: 1),
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
    }
}
