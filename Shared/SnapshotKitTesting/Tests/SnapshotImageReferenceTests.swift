import ImageIO
import SnapshotKit
@_spi(Testing) @testable import SnapshotKitTesting
import SwiftUI
import Testing
import UIKit

@MainActor
struct SnapshotImageReferenceTests {
    private func png(_ panels: [SnapshotPanelCapture]) async throws -> Data {
        try await SnapshotImageGrid.capture(panels: panels, named: "Reference").pngData()
    }

    @Test func additionalPanelsCannotHideALocalRegression() async throws {
        let old = (0 ..< 8).map { comparisonPanel("theme-\($0)") }
        let new = (0 ..< 8).map { comparisonPanel(
            "theme-\($0)",
            changed: $0 == 0,
        ) }
        let failure = try await SnapshotImageReference.comparePanels(
            referencePNG: png(old),
            panels: new,
        )
        #expect(failure?.message.contains("Panel theme-0") == true)
    }

    @Test func identicalPanelsPassAndGeometryChangesRemainObservable() async throws {
        let old = [comparisonPanel("a")]
        let same = [comparisonPanel("a")]
        #expect(try await SnapshotImageReference
            .comparePanels(referencePNG: png(old), panels: same) == nil)
        let taller = [comparisonPanel("a", height: 100)]
        #expect(try await SnapshotImageReference
            .comparePanels(referencePNG: png(old), panels: taller) != nil)
    }

    @Test func reportsEveryFailingPanel() async throws {
        let old = [comparisonPanel("a"), comparisonPanel("b")]
        let new = [
            comparisonPanel("a", changed: true),
            comparisonPanel("b", changed: true),
        ]
        let failure = try await SnapshotImageReference.comparePanels(
            referencePNG: png(old),
            panels: new,
        )
        #expect(failure?.message.contains("Panel a") == true)
        #expect(failure?.message.contains("Panel b") == true)
    }

    @Test func embeddedMapRoundTripsAndMissingMapFails() async throws {
        let sheet = [comparisonPanel("a", scale: 3)]
        let reference = try await SnapshotImageGrid.capture(panels: sheet, named: "RoundTrip")
        let data = try reference.pngData()
        let decoded = try SnapshotImageReference(png: data)
        #expect(decoded.layout == reference.layout)
        let bare = reference.capture.pngData
        #expect(try exifColorSpace(in: bare) == exifColorSpace(in: data))
        #expect(SnapshotImageReference.comparePanels(referencePNG: bare, panels: sheet)?.message
            .contains("missing") == true)
        #expect(SnapshotImageReference.strategy(panelFailure: nil).diffing
            .diffV2(bare, bare) == nil)
        #expect(SnapshotImageReference.strategy(panelFailure: nil).diffing
            .diffV2(data, bare)?.0.contains("metadata changed") == true)
    }

    private func exifColorSpace(in png: Data) throws -> NSNumber {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        return try #require(exif?[kCGImagePropertyExifColorSpace] as? NSNumber)
    }

    @Test func corruptPNGProducesExplicitFailure() {
        let failure = SnapshotImageReference.strategy(panelFailure: nil).diffing.diffV2(
            Data([1, 2, 3]),
            Data([4]),
        )
        #expect(failure?.0.contains("Cannot compare snapshot PNG") == true)
    }

    @Test func identityAndOrderingChangesCannotReinterpretPixels() async throws {
        let old = [comparisonPanel("a"), comparisonPanel("b")]
        for names in [["b", "a"], ["a", "c"]] {
            let new = names.map { comparisonPanel($0) }
            let failure = try await SnapshotImageReference.comparePanels(
                referencePNG: png(old),
                panels: new,
            )
            #expect(failure?.message.contains("membership") == true)
        }
    }

    @Test func invalidBoundsAndDuplicateIdentitiesFailExplicitly() async throws {
        let sheet = [comparisonPanel("a")]
        let sheetReference = try await SnapshotImageGrid.capture(panels: sheet, named: "Invalid")
        let layout = try #require(sheetReference.layout)
        let panel = layout.panels[0]
        let invalidLayouts = [
            SnapshotComparisonLayout(panels: [panel, panel], pixelSize: layout.pixelSize),
            SnapshotComparisonLayout(panels: [.init(
                identity: panel.identity,
                label: panel.label,
                bounds: CGRect(x: -1, y: 0, width: 100, height: 80),
            )], pixelSize: layout.pixelSize),
            SnapshotComparisonLayout(panels: [panel], pixelSize: .zero),
        ]
        for layout in invalidLayouts {
            let data = try SnapshotImageReference(capture: sheetReference.capture, layout: layout)
                .pngData()
            #expect(throws: (any Error).self) { try SnapshotImageReference(png: data) }
            #expect(SnapshotImageReference.comparePanels(referencePNG: data, panels: sheet)?
                .message.contains("Cannot compare") == true)
        }
    }

    @Test func panelVerdictSurvivesWholeSheetTolerance() async throws {
        let old = (0 ..< 8).map { comparisonPanel("theme-\($0)") }
        let new = (0 ..< 8).map {
            comparisonPanel("theme-\($0)", changed: $0 == 0)
        }
        let oldPNG = try await png(old)
        let failure = try #require(SnapshotImageReference.comparePanels(
            referencePNG: oldPNG,
            panels: new,
        ))
        let verdict = try await SnapshotImageReference.strategy(panelFailure: failure).diffing
            .diffV2(
                oldPNG,
                png(new),
            )
        #expect(verdict?.0.contains("Panel theme-0") == true)
    }
}
