@testable import BroadwayUI
import SwiftUI
import Testing
import ViewDocumentCore

@MainActor
struct BArtworkLayerTests {
    @Test func exteriorMaskProtectsNativeContentAndStopsAtPaintBounds() {
        let clip = BArtworkClip(
            shape: Rectangle(),
            host: CGSize(width: 100, height: 80),
            paintBounds: .init(x: -10, y: -10, width: 120, height: 100),
            plane: .exterior,
        )
        let path = clip.path(in: CGRect(x: 0, y: 0, width: 120, height: 100))
        #expect(!path.contains(CGPoint(x: 60, y: 50), eoFill: true))
        #expect(path.contains(CGPoint(x: 12, y: 50), eoFill: true))
        #expect(path.contains(CGPoint(x: 5, y: 50), eoFill: true))
        #expect(!path.contains(CGPoint(x: -1, y: 50), eoFill: true))
        #expect(!path.contains(CGPoint(x: 121, y: 50), eoFill: true))
    }

    @Test func interiorMaskFollowsSurfaceCorners() {
        let clip = BArtworkClip(
            shape: RoundedRectangle(cornerRadius: 20),
            host: CGSize(width: 100, height: 80),
            paintBounds: .init(x: 0, y: 0, width: 100, height: 80),
            plane: .interior,
        )
        let path = clip.path(in: CGRect(x: 0, y: 0, width: 100, height: 80))
        #expect(!path.contains(CGPoint(x: 1, y: 1)))
        #expect(path.contains(CGPoint(x: 50, y: 40)))
    }

    @Test func exteriorBandInsetsTheRoundedContourWithoutRescalingIt() {
        let clip = BArtworkClip(
            shape: RoundedRectangle(cornerRadius: 20),
            host: CGSize(width: 100, height: 80),
            paintBounds: .init(x: 0, y: 0, width: 100, height: 80),
            plane: .exterior,
        )
        let path = clip.path(in: CGRect(x: 0, y: 0, width: 100, height: 80))
        #expect(!path.contains(CGPoint(x: 20, y: 20), eoFill: true))
        #expect(path.contains(CGPoint(x: 10, y: 20), eoFill: true))
    }

    @Test func overflowDoesNotChangeLayoutSize() throws {
        let placement = try BArtworkPlacement(.init(
            anchor: .bottomTrailing,
            size: .fixed(width: 100, height: 100),
            offset: .init(x: 20, y: 20),
            plane: .exterior,
            outsets: .init(top: 0, leading: 0, bottom: 20, trailing: 20),
        ))
        let view = Color.white.frame(width: 80, height: 60).overlay {
            BArtworkLayer(placement: placement, shape: Rectangle(), role: .essential) {
                Color.orange.scaleEffect(100)
            }
        }
        let image = try #require(ImageRenderer(content: view).uiImage)
        #expect(image.size == CGSize(width: 80, height: 60))
    }
}
