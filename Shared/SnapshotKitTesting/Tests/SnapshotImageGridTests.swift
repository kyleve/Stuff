import SnapshotKit
@testable import SnapshotKitTesting
import SwiftUI
import Testing
import UIKit

@MainActor
struct SnapshotImageGridTests {
    @Test func preservesExactPixelsAndWrapsRows() async throws {
        let panels = [
            comparisonPanel("a", height: 1609.0 / 3.0, changed: true),
            comparisonPanel("b", height: 120),
            comparisonPanel("c", changed: true),
        ]
        let capture = try await SnapshotImageGrid.capture(panels: panels, named: "Grid")
        let layout = try #require(capture.layout)
        let pixels = try #require(capture.image.cgImage)
        #expect(layout.pixelSize == CGSize(width: pixels.width, height: pixels.height))
        #expect(layout.panels.map(\.identity) == panels.map(\.identity))
        #expect(layout.panels[2].bounds.minX == layout.panels[0].bounds.minX)
        #expect(layout.panels[2].bounds.minY > layout.panels[0].bounds.maxY)
        for (panel, placement) in zip(panels, layout.panels) {
            let crop = try #require(pixels.cropping(to: placement.bounds))
            let original = try #require(panel.image.cgImage)
            #expect(crop.width == original.width)
            #expect(crop.height == original.height)
            let diff = Snapshotting<UIImage, UIImage>.image(precision: 1, perceptualPrecision: 1)
            #expect(diff.diffing.diffV2(
                UIImage(cgImage: original),
                UIImage(cgImage: crop),
            ) == nil)
        }
        #expect(try SnapshotImageReference(png: capture.pngData()).layout == layout)
    }

    @Test func wrapsLongLabelsWithoutClippingOrMovingPanelPixels() async throws {
        let panel = comparisonPanel("A long descriptive panel label that needs multiple lines")
        let capture = try await SnapshotImageGrid.capture(panels: [panel], named: "Label")
        let layout = try #require(capture.layout)
        #expect(layout.panels[0].bounds.minY > 48 * capture.image.scale)
        #expect(layout.panels[0].bounds.width == panel.image.size.width * capture.image.scale)
    }
}
