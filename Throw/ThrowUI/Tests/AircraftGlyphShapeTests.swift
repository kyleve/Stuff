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
}
