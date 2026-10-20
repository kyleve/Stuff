import SnapshotKit
@testable import SnapshotKitTesting
import SwiftUI
import Testing
import UIKit

@MainActor
struct SnapshotComparisonSheetTests {
    private func panel(
        _ name: String,
        height: CGFloat = 80,
        scale: CGFloat = 1,
        changed: Bool = false,
    ) -> SnapshotComparisonSheet.Panel {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 100, height: height),
            format: format,
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: height))
            if changed {
                UIColor.black.setFill()
                context.fill(CGRect(x: 20, y: 20, width: 4, height: 4))
            }
        }
        return .init(identity: .init(rawValue: name), label: name, image: image)
    }

    @Test func roundsFractionalPointSizesToExactPixels() throws {
        let sheet = try SnapshotComparisonSheet(panels: [panel(
            "a",
            height: 1609.0 / 3.0,
            scale: 3,
        )])
        let pixels = try #require(sheet.image.cgImage)
        #expect(sheet.layout.pixelSize.height == CGFloat(pixels.height))
        #expect(sheet.layout.pixelSize.width == CGFloat(pixels.width))
        for panel in sheet.layout.panels {
            #expect(panel.bounds.minY == panel.bounds.minY.rounded())
            #expect(panel.bounds.height == panel.bounds.height.rounded())
        }
        let reference = try SnapshotComparisonSheet.strategy(layout: sheet.layout).diffing
            .fromData(#require(sheet.image.pngData()))
        #expect(SnapshotComparisonSheet.strategy(layout: sheet.layout).diffing.diff(
            reference,
            sheet.image,
        ) == nil)
    }

    @Test func wrapsWithoutScalingAndPreservesPanelHeights() throws {
        let sheet = try SnapshotComparisonSheet(panels: [
            panel("a"),
            panel("b", height: 120),
            panel("c"),
        ])
        #expect(sheet.layout.panels.map(\.identity.rawValue) == ["a", "b", "c"])
        #expect(sheet.layout.panels[0].bounds.width == 100)
        #expect(sheet.layout.panels[1].bounds.height == 120)
        #expect(sheet.layout.panels[2].bounds.minX == sheet.layout.panels[0].bounds.minX)
        #expect(sheet.layout.panels[2].bounds.minY > sheet.layout.panels[1].bounds.maxY)
    }

    @Test func additionalPanelsCannotHideALocalRegression() throws {
        let old = try SnapshotComparisonSheet(panels: (0 ..< 8).map { panel("theme-\($0)") })
        let new = try SnapshotComparisonSheet(panels: (0 ..< 8).map { panel(
            "theme-\($0)",
            changed: $0 == 0,
        ) })
        let failure = SnapshotComparisonSheet.strategy(layout: new.layout).diffing.diff(
            old.image,
            new.image,
        )
        #expect(failure?.0.contains("Panel theme-0") == true)
    }

    @Test func identicalPanelsPassAndGeometryChangesRemainObservable() throws {
        let old = try SnapshotComparisonSheet(panels: [panel("a")])
        let same = try SnapshotComparisonSheet(panels: [panel("a")])
        #expect(SnapshotComparisonSheet.strategy(layout: same.layout).diffing.diff(
            old.image,
            same.image,
        ) == nil)
        let taller = try SnapshotComparisonSheet(panels: [panel("a", height: 100)])
        #expect(old.layout != taller.layout)
        #expect(SnapshotComparisonSheet.strategy(layout: taller.layout).diffing.diff(
            old.image,
            taller.image,
        ) != nil)
    }
}
