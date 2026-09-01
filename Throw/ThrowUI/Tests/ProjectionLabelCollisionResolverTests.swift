import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct ProjectionLabelCollisionResolverTests {
    @Test(arguments: ProjectionMode.allCases)
    func collisionUsesPhysicalRangeInsteadOfScreenRadius(_ mode: ProjectionMode) throws {
        var resolver = ProjectionLabelCollisionResolver()
        let frame = try ProjectionFrame.testing(
            mode: mode,
            generatedAt: .init(timeIntervalSince1970: 100),
            geography: nil,
            geographyOpacity: 1,
            marks: [
                mark(id: "far", x: 0.51, range: 50),
                mark(id: "near", x: 0.55, range: 5),
            ],
        )

        let resolved = resolver.resolve(frame)

        #expect(resolved.marks.count == 2)
        #expect(resolved.marks.first(where: { $0.id.rawValue == "icao/near" })?.label != nil)
        #expect(resolved.marks.first(where: { $0.id.rawValue == "icao/far" })?.label == nil)
    }

    @Test func rangeHysteresisKeepsThePreviousWinnerWithinQuarterMile() throws {
        var resolver = ProjectionLabelCollisionResolver()
        let date = Date(timeIntervalSince1970: 100)
        _ = try resolver.resolve(ProjectionFrame.testing(
            mode: .map,
            generatedAt: date,
            geography: nil,
            geographyOpacity: 1,
            marks: [
                mark(id: "alpha", x: 0.51, range: 10),
                mark(id: "bravo", x: 0.55, range: 10.1),
            ],
        ))

        let withinTolerance = try resolver.resolve(ProjectionFrame.testing(
            mode: .map,
            generatedAt: date.addingTimeInterval(1),
            geography: nil,
            geographyOpacity: 1,
            marks: [
                mark(id: "alpha", x: 0.51, range: 10.2),
                mark(id: "bravo", x: 0.55, range: 10),
            ],
        ))

        #expect(withinTolerance.marks.first(where: { $0.id.rawValue == "icao/alpha" })?
            .label != nil)
        #expect(withinTolerance.marks.first(where: { $0.id.rawValue == "icao/bravo" })?
            .label == nil)
    }

    @Test func staleAndLabelOpacitySurviveLabelResolution() throws {
        var resolver = ProjectionLabelCollisionResolver()
        let stale = try mark(
            id: "stale",
            x: 0.5,
            range: 1,
            opacity: 0.5,
            labelOpacity: 0.4,
        )

        let resolved = resolver.resolve(ProjectionFrame.testing(
            mode: .map,
            generatedAt: .init(timeIntervalSince1970: 100),
            geography: nil,
            geographyOpacity: 1,
            marks: [stale],
        ))

        #expect(resolved.marks.first?.opacity == 0.5)
        #expect(resolved.marks.first?.labelOpacity == 0.4)
        #expect(resolved.marks.first?.label != nil)
    }

    @Test func detailOnlyLabelsUseSmallerCollisionBounds() throws {
        let date = Date(timeIntervalSince1970: 100)
        let headline = try ProjectionFrame.testing(
            mode: .map,
            generatedAt: date,
            geography: nil,
            geographyOpacity: 1,
            marks: [
                mark(id: "alpha", x: 0.5, range: 1, labelRole: .headline),
                mark(id: "bravo", x: 0.557, range: 2, labelRole: .headline),
            ],
        )
        let detail = try ProjectionFrame.testing(
            mode: .map,
            generatedAt: date,
            geography: nil,
            geographyOpacity: 1,
            marks: [
                mark(id: "alpha", x: 0.5, range: 1, labelRole: .detail),
                mark(id: "bravo", x: 0.557, range: 2, labelRole: .detail),
            ],
        )

        var headlineResolver = ProjectionLabelCollisionResolver()
        var detailResolver = ProjectionLabelCollisionResolver()
        #expect(headlineResolver.resolve(headline).marks.compactMap(\.label).count == 1)
        #expect(detailResolver.resolve(detail).marks.compactMap(\.label).count == 2)
    }

    private func mark(
        id: String,
        x: Double,
        range: Double,
        opacity: Double = 1,
        labelOpacity: Double = 1,
        labelRole: ProjectionLabelRole = .headline,
    ) throws -> ProjectedMark {
        try ProjectedMark(
            id: #require(AircraftID(kind: .icao, rawValue: id)).layerMarkID,
            point: ProjectionPoint(x: x, y: 0.5),
            range: NauticalMiles(value: range),
            glyph: .aircraft(.unknownAirborne),
            label: ProjectionLabel(primary: id, primaryRole: labelRole, secondary: nil),
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: opacity,
            labelOpacity: labelOpacity,
            altitudeIsApproximate: false,
        )
    }
}
