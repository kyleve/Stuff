import Foundation
import Testing
import ViewDocumentCore

struct ViewArtworkPlacementTests {
    @Test func hostGuttersShrinkArtworkBeforeNativeContent() throws {
        let placement = ViewArtworkPlacement(
            anchor: .bottomTrailing,
            size: .fixed(width: 100, height: 80),
            offset: .init(x: 40, y: 20),
            plane: .exterior,
            outsets: .init(top: 0, leading: 0, bottom: 20, trailing: 40),
        )
        try placement.validate()
        let geometry = placement.geometry(
            in: .init(width: 300, height: 100),
            rightToLeft: false,
            maximumOutsets: .init(top: 0, leading: 0, bottom: 20, trailing: 10),
        )
        #expect(geometry.frame.width == 25)
        #expect(geometry.frame.height == 20)
        #expect(geometry.frame.x == 285)
        #expect(geometry.paintBounds.width == 310)
        #expect(geometry.paintBounds.height == 105)
        let hidden = placement.geometry(
            in: .init(width: 300, height: 100),
            rightToLeft: true,
            maximumOutsets: .zero,
        )
        #expect(hidden.frame.width == 0)
        #expect(hidden.paintBounds.width == 300)
    }

    @Test func separatesOverflowFromHostLayoutAndMirrorsDirection() throws {
        let placement = ViewArtworkPlacement(
            anchor: .bottomTrailing,
            size: .fixed(width: 80, height: 60),
            offset: .init(x: 12, y: 24),
            plane: .exterior,
            outsets: .init(top: 0, leading: 4, bottom: 24, trailing: 12),
        )
        try placement.validate()
        let host = ViewArtworkPlacement.Extent(width: 300, height: 160)
        let leftToRight = placement.geometry(in: host, rightToLeft: false)
        let rightToLeft = placement.geometry(in: host, rightToLeft: true)
        #expect(leftToRight.frame == ViewArtworkPlacement.Frame(
            x: 232,
            y: 124,
            width: 80,
            height: 60,
        ))
        #expect(leftToRight.paintBounds == ViewArtworkPlacement.Frame(
            x: -4,
            y: 0,
            width: 316,
            height: 184,
        ))
        #expect(rightToLeft.frame == ViewArtworkPlacement.Frame(
            x: -12,
            y: 124,
            width: 80,
            height: 60,
        ))
        #expect(rightToLeft.paintBounds == ViewArtworkPlacement.Frame(
            x: -12,
            y: 0,
            width: 316,
            height: 184,
        ))
    }

    @Test func narrowHostsScaleArtworkAndOffsetTogether() throws {
        let placement = ViewArtworkPlacement(
            anchor: .bottom,
            size: .fixed(width: 200, height: 100),
            offset: .init(x: 0, y: 20),
            plane: .exterior,
            outsets: .init(top: 0, leading: 0, bottom: 20, trailing: 0),
        )
        try placement.validate()
        #expect(placement.geometry(
            in: ViewArtworkPlacement.Extent(width: 100, height: 80),
            rightToLeft: false,
        ).frame
            == ViewArtworkPlacement.Frame(x: 0, y: 40, width: 100, height: 50))
    }

    @Test func relativeSizingHasFinitePointCaps() throws {
        let placement = ViewArtworkPlacement(
            anchor: .center,
            size: .relative(width: 1, height: 0.5, maximumWidth: 400, maximumHeight: 300),
            offset: .zero,
            plane: .interior,
            outsets: .zero,
        )
        try placement.validate()
        let geometry = placement.geometry(
            in: ViewArtworkPlacement.Extent(width: 2000, height: 2000),
            rightToLeft: false,
        )
        #expect(geometry.frame.size == ViewArtworkPlacement.Extent(width: 400, height: 300))
        #expect(try JSONDecoder().decode(
            ViewArtworkPlacement.self,
            from: JSONEncoder().encode(placement),
        ) == placement)
    }

    @Test(arguments: [Double.nan, .infinity, -1, 129])
    func rejectsUnboundedOutsets(value: Double) {
        let placement = ViewArtworkPlacement(
            anchor: .center,
            size: .fixed(width: 80, height: 60),
            offset: .zero,
            plane: .exterior,
            outsets: .init(top: value, leading: 0, bottom: 0, trailing: 0),
        )
        #expect(throws: ViewDocumentValidationError.self) { try placement.validate() }
    }

    @Test func interiorCannotClaimOverflow() {
        let placement = ViewArtworkPlacement(
            anchor: .center,
            size: .fixed(width: 80, height: 60),
            offset: .zero,
            plane: .interior,
            outsets: .init(top: 1, leading: 0, bottom: 0, trailing: 0),
        )
        #expect(throws: ViewDocumentValidationError.self) { try placement.validate() }
    }
}
