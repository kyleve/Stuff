import CoreGraphics
import SwiftUI
import Testing
import ThrowCore
@testable import ThrowUI

struct AircraftGlyphShapeTests {
    @Test(arguments: AircraftVisualFamily.allCases)
    func everyFamilyUsesTheRequestedRectangleAndHasAnAccent(
        _ family: AircraftVisualFamily,
    ) {
        let rect = CGRect(x: -12, y: -8, width: 24, height: 16)
        let body = AircraftGlyphShape(family: family).path(in: rect)
        let accent = AircraftAccentShape(family: family).path(in: rect)
        let bounds = body.boundingRect

        #expect(body.isEmpty == false)
        #expect(rect.contains(bounds))
        #expect(abs(bounds.midX - rect.midX) < 0.000_001)
        #expect(accent.isEmpty == false)
        #expect(rect.contains(accent.boundingRect))
    }

    @Test
    func familiesRemainDistinctAtTheStandardMarkSize() {
        let rect = CGRect(x: 0, y: 0, width: 12, height: 12)
        let masks = AircraftVisualFamily.allCases.map { family in
            let path = AircraftGlyphShape(family: family).path(in: rect)
            return (0 ..< 12).flatMap { y in
                (0 ..< 12).map { x in
                    path.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
                }
            }
        }

        #expect(Set(masks).count == AircraftVisualFamily.allCases.count)
    }

    @Test(arguments: AircraftVisualFamily.allCases)
    func overlappingPartsRemainSolid(_ family: AircraftVisualFamily) {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = AircraftGlyphShape(family: family).path(in: rect)

        #expect(path.contains(CGPoint(x: 50, y: 45)))
        #expect(path.contains(CGPoint(x: 50, y: 88)))
    }
}
