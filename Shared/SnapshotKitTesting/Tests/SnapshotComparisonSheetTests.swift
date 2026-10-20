import SnapshotKit
@testable import SnapshotKitTesting
import SwiftUI
import Testing
import UIKit

@MainActor
struct SnapshotComparisonSheetTests {
    @Test func roundsFractionalPointSizesToExactPixels() throws {
        let sheet = try SnapshotComparisonSheet(panels: [comparisonPanel(
            "a",
            height: 1609.0 / 3.0,
            scale: 3,
        )])
        let pixels = try #require(sheet.render().cgImage)
        #expect(sheet.layout.pixelSize.height == CGFloat(pixels.height))
        #expect(sheet.layout.pixelSize.width == CGFloat(pixels.width))
        for panel in sheet.layout.panels {
            #expect(panel.bounds.minY == panel.bounds.minY.rounded())
            #expect(panel.bounds.height == panel.bounds.height.rounded())
        }
        let reference = try SnapshotImageReference(image: sheet.render(), layout: sheet.layout)
            .pngData()
        #expect(try SnapshotImageReference.strategy(panelFailure: nil).diffing.diffV2(
            reference,
            SnapshotImageReference(image: sheet.render(), layout: sheet.layout).pngData(),
        ) == nil)
    }

    @Test func wrapsWithoutScalingAndPreservesPanelHeights() throws {
        let sheet = try SnapshotComparisonSheet(panels: [
            comparisonPanel("a"),
            comparisonPanel("b", height: 120),
            comparisonPanel("c"),
        ])
        #expect(sheet.layout.panels.map(\.identity.rawValue) == ["a", "b", "c"])
        #expect(sheet.layout.panels[0].bounds.width == 100)
        #expect(sheet.layout.panels[1].bounds.height == 120)
        #expect(sheet.layout.panels[2].bounds.minX == sheet.layout.panels[0].bounds.minX)
        #expect(sheet.layout.panels[2].bounds.minY > sheet.layout.panels[1].bounds.maxY)
    }
}
