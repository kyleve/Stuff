import CoreGraphics
import SwiftUI
import Testing
@testable import ThrowUI

struct AircraftGlyphShapeTests {
    @Test func pathUsesTheRequestedRectangleOriginAndExtent() {
        let rect = CGRect(x: -12, y: -8, width: 24, height: 16)
        let bounds = AircraftGlyphShape().path(in: rect).boundingRect

        #expect(abs(bounds.minX - rect.minX) < 0.000_001)
        #expect(abs(bounds.minY - rect.minY) < 0.000_001)
        #expect(abs(bounds.maxX - rect.maxX) < 0.000_001)
        #expect(abs(bounds.maxY - rect.maxY) < 0.000_001)
    }
}
