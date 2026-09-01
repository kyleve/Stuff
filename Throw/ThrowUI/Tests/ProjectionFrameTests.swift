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
        let geography = lineCollection(id: 1, styleID: .geography(.coastline))
        let network = lineCollection(id: 2, styleID: .transitRoute)
        let vehicle = try transitVehicleMark(rawID: "vehicle")
        let frame = present(.transit(TransitProjectedFrame(
            generatedAt: testDate,
            geography: .testing(lines: geography),
            network: .testing(lines: network),
            vehicles: ProjectedLayerFrame(marks: [vehicle]),
        )))

        #expect(frame.experienceID == .transit)
        #expect(frame.mode == .map)
        #expect(frame.layers.map(\.id) == [.geography, .transitNetwork, .transitVehicles])
        #expect(frame.layers.map(\.content) == [
            .lines(geography),
            .lines(network),
            .marks([vehicle]),
        ])
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
        let geography = lineCollection(id: 7, styleID: .geography(.coastline))
        let first = try aircraftMark(rawID: "first")
        let replacement = try aircraftMark(rawID: "replacement")
        let frame = present(.airAndSpace(.map(AirAndSpaceMapProjectedFrame(
            generatedAt: testDate,
            geography: .testing(lines: geography),
            flights: ProjectedLayerFrame(marks: [first]),
            satellites: nil,
        ))))

        let replaced = frame.replacingMarks([replacement])

        #expect(replaced.experienceID == .airAndSpace)
        #expect(replaced.mode == .map)
        #expect(replaced.geography == geography)
        #expect(replaced.marks == [replacement])
        #expect(replaced.description == "<ProjectionFrame mode=map marks=1 geography=1>")
    }

    private var testDate: Date {
        Date(timeIntervalSince1970: 100)
    }

    private func lineCollection(
        id: UInt64,
        styleID: ProjectionLineStyleID,
    ) -> ProjectedLineCollection {
        ProjectedLineCollection.testing(
            id: ProjectionLineRevisionID.testing(rawValue: id),
            segments: [ProjectedLineSegment(
                styleID: styleID,
                start: ProjectionPoint(x: 0.1, y: 0.2),
                end: ProjectionPoint(x: 0.8, y: 0.9),
                startsNewSubpath: true,
            )],
        )
    }

    private func aircraftMark(rawID: String) throws -> ProjectedMark {
        try projectedMark(
            id: #require(AircraftID(kind: .icao, rawValue: rawID)).layerMarkID,
            glyph: .aircraft(.unknownAirborne),
        )
    }

    private func starMark(rawID: String) throws -> ProjectedMark {
        try projectedMark(
            id: .star(#require(StarID(rawValue: rawID))),
            glyph: .star,
        )
    }

    private func transitVehicleMark(rawID: String) throws -> ProjectedMark {
        try projectedMark(
            id: .transitVehicle(#require(TransitVehicleID(rawValue: rawID))),
            glyph: .aircraft(.unknownAirborne),
        )
    }

    private func projectedMark(
        id: LayerMarkID,
        glyph: ProjectionGlyph,
    ) throws -> ProjectedMark {
        try ProjectedMark(
            id: id,
            point: ProjectionPoint(x: 0.5, y: 0.5),
            range: NauticalMiles(value: 1),
            glyph: glyph,
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
    }
}
