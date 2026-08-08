import SwiftUI
import Testing
@testable import WhereUI

struct RegionArtworkTransformTests {
    @Test func fitsAndCentersProjectedGeometryUsingTheArtworkSpec() throws {
        let path = Path { $0.addRect(CGRect(x: 0, y: 0, width: 100, height: 50)) }
        let style = try #require(WhereStylesheet.default.card.regular.regionShape?.watermark)
        let transform = try #require(RegionArtworkTransform(
            path: path,
            size: CGSize(width: 320, height: 180),
            style: style,
        ))

        let expectedScale = min(320 * style.extent.width / 100, 180 * style.extent.height / 50)
            * style.scale
        #expect(abs(transform.scale - expectedScale) < 0.0001)
        #expect(abs(transform.translation.x - (320 * style.center.x / expectedScale - 50)) < 0.0001)
        #expect(abs(transform.translation.y - (180 * style.center.y / expectedScale - 25)) < 0.0001)
    }
}
