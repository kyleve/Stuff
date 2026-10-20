import SnapshotKit
@testable import SnapshotKitTesting
import SwiftUI
import Testing
import UIKit

@MainActor
struct SnapshotImageReferenceTests {
    private func png(_ sheet: SnapshotComparisonSheet) throws -> Data {
        try SnapshotImageReference(image: sheet.render(), layout: sheet.layout).pngData()
    }

    @Test func additionalPanelsCannotHideALocalRegression() throws {
        let old = try SnapshotComparisonSheet(panels: (0 ..< 8)
            .map { comparisonPanel("theme-\($0)") })
        let new = try SnapshotComparisonSheet(panels: (0 ..< 8).map { comparisonPanel(
            "theme-\($0)",
            changed: $0 == 0,
        ) })
        let failure = try SnapshotImageReference.comparePanels(referencePNG: png(old), sheet: new)
        #expect(failure?.message.contains("Panel theme-0") == true)
    }

    @Test func identicalPanelsPassAndGeometryChangesRemainObservable() throws {
        let old = try SnapshotComparisonSheet(panels: [comparisonPanel("a")])
        let same = try SnapshotComparisonSheet(panels: [comparisonPanel("a")])
        #expect(try SnapshotImageReference
            .comparePanels(referencePNG: png(old), sheet: same) == nil)
        let taller = try SnapshotComparisonSheet(panels: [comparisonPanel("a", height: 100)])
        #expect(old.layout != taller.layout)
        #expect(try SnapshotImageReference
            .comparePanels(referencePNG: png(old), sheet: taller) != nil)
    }

    @Test func reportsEveryFailingPanel() throws {
        let old = try SnapshotComparisonSheet(panels: [comparisonPanel("a"), comparisonPanel("b")])
        let new = try SnapshotComparisonSheet(panels: [
            comparisonPanel("a", changed: true),
            comparisonPanel("b", changed: true),
        ])
        let failure = try SnapshotImageReference.comparePanels(referencePNG: png(old), sheet: new)
        #expect(failure?.message.contains("Panel a") == true)
        #expect(failure?.message.contains("Panel b") == true)
    }

    @Test func embeddedMapRoundTripsAndMissingMapFails() throws {
        let sheet = try SnapshotComparisonSheet(panels: [comparisonPanel("a", scale: 3)])
        let data = try png(sheet)
        let decoded = try SnapshotImageReference(png: data)
        #expect(decoded.layout == sheet.layout)
        let bare = try #require(sheet.render().pngData())
        #expect(SnapshotImageReference.comparePanels(referencePNG: bare, sheet: sheet)?.message
            .contains("missing") == true)
        #expect(SnapshotImageReference.strategy(panelFailure: nil).diffing
            .diffV2(bare, bare) == nil)
        #expect(SnapshotImageReference.strategy(panelFailure: nil).diffing
            .diffV2(data, bare)?.0.contains("metadata changed") == true)
    }

    @Test func corruptPNGProducesExplicitFailure() {
        let failure = SnapshotImageReference.strategy(panelFailure: nil).diffing.diffV2(
            Data([1, 2, 3]),
            Data([4]),
        )
        #expect(failure?.0.contains("Cannot compare snapshot PNG") == true)
    }

    @Test func identityAndOrderingChangesCannotReinterpretPixels() throws {
        let old = try SnapshotComparisonSheet(panels: [comparisonPanel("a"), comparisonPanel("b")])
        for names in [["b", "a"], ["a", "c"]] {
            let new = try SnapshotComparisonSheet(panels: names.map { comparisonPanel($0) })
            let failure = try SnapshotImageReference.comparePanels(
                referencePNG: png(old),
                sheet: new,
            )
            #expect(failure?.message.contains("membership") == true)
        }
    }

    @Test func invalidBoundsAndDuplicateIdentitiesFailExplicitly() throws {
        let sheet = try SnapshotComparisonSheet(panels: [comparisonPanel("a")])
        let image = try sheet.render()
        let panel = sheet.layout.panels[0]
        let invalidLayouts = [
            SnapshotComparisonLayout(panels: [panel, panel], pixelSize: sheet.layout.pixelSize),
            SnapshotComparisonLayout(panels: [.init(
                identity: panel.identity,
                label: panel.label,
                bounds: CGRect(x: -1, y: 0, width: 100, height: 80),
            )], pixelSize: sheet.layout.pixelSize),
            SnapshotComparisonLayout(panels: [panel], pixelSize: .zero),
        ]
        for layout in invalidLayouts {
            let data = try SnapshotImageReference(image: image, layout: layout).pngData()
            #expect(throws: (any Error).self) { try SnapshotImageReference(png: data) }
            #expect(SnapshotImageReference.comparePanels(referencePNG: data, sheet: sheet)?
                .message.contains("Cannot compare") == true)
        }
    }

    @Test func panelVerdictSurvivesWholeSheetTolerance() throws {
        let old = try SnapshotComparisonSheet(panels: (0 ..< 8)
            .map { comparisonPanel("theme-\($0)") })
        let new = try SnapshotComparisonSheet(panels: (0 ..< 8).map {
            comparisonPanel("theme-\($0)", changed: $0 == 0)
        })
        let oldPNG = try png(old)
        let failure = try #require(SnapshotImageReference.comparePanels(
            referencePNG: oldPNG,
            sheet: new,
        ))
        let verdict = try SnapshotImageReference.strategy(panelFailure: failure).diffing.diffV2(
            oldPNG,
            png(new),
        )
        #expect(verdict?.0.contains("Panel theme-0") == true)
    }
}
