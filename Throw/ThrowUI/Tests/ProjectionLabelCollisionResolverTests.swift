import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct ProjectionLabelCollisionResolverTests {
    @Test(arguments: ProjectionMode.allCases)
    func collisionUsesPhysicalRangeInsteadOfScreenRadius(_ mode: ProjectionMode) throws {
        var resolver = ProjectionLabelCollisionResolver()
        let frame = try ProjectionFrame(
            mode: mode,
            generatedAt: .init(timeIntervalSince1970: 100),
            marks: [
                mark(id: "far", x: 0.51, range: 50),
                mark(id: "near", x: 0.55, range: 5),
            ],
        )

        let resolved = resolver.resolve(frame)

        #expect(resolved.marks.count == 2)
        #expect(resolved.marks.first(where: { $0.id.rawValue == "near" })?.label != nil)
        #expect(resolved.marks.first(where: { $0.id.rawValue == "far" })?.label == nil)
    }

    @Test func rangeHysteresisKeepsThePreviousWinnerWithinQuarterMile() throws {
        var resolver = ProjectionLabelCollisionResolver()
        let date = Date(timeIntervalSince1970: 100)
        _ = try resolver.resolve(ProjectionFrame(
            mode: .map,
            generatedAt: date,
            marks: [
                mark(id: "alpha", x: 0.51, range: 10),
                mark(id: "bravo", x: 0.55, range: 10.1),
            ],
        ))

        let withinTolerance = try resolver.resolve(ProjectionFrame(
            mode: .map,
            generatedAt: date.addingTimeInterval(1),
            marks: [
                mark(id: "alpha", x: 0.51, range: 10.2),
                mark(id: "bravo", x: 0.55, range: 10),
            ],
        ))

        #expect(withinTolerance.marks.first(where: { $0.id.rawValue == "alpha" })?.label != nil)
        #expect(withinTolerance.marks.first(where: { $0.id.rawValue == "bravo" })?.label == nil)
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

        let resolved = resolver.resolve(ProjectionFrame(
            mode: .map,
            generatedAt: .init(timeIntervalSince1970: 100),
            marks: [stale],
        ))

        #expect(resolved.marks.first?.opacity == 0.5)
        #expect(resolved.marks.first?.labelOpacity == 0.4)
        #expect(resolved.marks.first?.label != nil)
    }

    private func mark(
        id: String,
        x: Double,
        range: Double,
        opacity: Double = 1,
        labelOpacity: Double = 1,
    ) throws -> ProjectedMark {
        try ProjectedMark(
            id: LayerMarkID(layerID: .flights, namespace: .aircraft, rawValue: id),
            point: ProjectionPoint(x: x, y: 0.5),
            range: NauticalMiles(value: range),
            glyph: .aircraft(isGrounded: false),
            label: ProjectionLabel(primary: id, secondary: nil),
            orientationDegrees: nil,
            opacity: opacity,
            labelOpacity: labelOpacity,
            altitudeIsApproximate: false,
        )
    }
}
