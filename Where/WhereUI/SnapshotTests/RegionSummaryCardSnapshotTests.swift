@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import Testing
@testable import WhereUI

@MainActor
struct RegionSummaryCardSnapshotTests {
    @Test func componentThemes() async {
        await assertSnapshots(of: RegionSummaryCard.self)
    }

    @Test func cardWatermarkRoundsASharpCoastalTipAtItsProjectedWidth() throws {
        let headland = Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 20, y: 2.5))
            path.addLine(to: CGPoint(x: 0, y: 5))
            path.closeSubpath()
        }
        let artwork = RegionOutlineArtwork(
            path: headland,
            tint: .black,
            style: .init(
                center: CGPoint(x: 0.5, y: 0.5),
                extent: CGSize(width: 0.5, height: 0.5),
                scale: 1,
                fillOpacity: 0,
                stroke: .init(opacity: 1, width: 4),
            ),
        )
        let renderer = ImageRenderer(content: artwork.frame(width: 80, height: 40))
        renderer.scale = 2
        let image = try #require(renderer.uiImage)

        // The 2× projection places the tip at (60, 20). Its four-point stroke
        // should extend two screen points beyond it, even at this sharp turn.
        let inside = image.probePixel(atUnitPoint: CGPoint(x: 61.0 / 80, y: 0.5))
        let outside = image.probePixel(atUnitPoint: CGPoint(x: 63.0 / 80, y: 0.5))
        #expect(inside.alpha > 0.95)
        #expect(outside.alpha == 0)
    }
}
