import SnapshotKit
import SnapshotTesting
@_spi(Testing) @testable import SnapshotKitTesting
import SwiftUI
import Testing
import UIKit

@MainActor
struct SnapshotImageReferenceTests {
    @Test func oversizedMatchingReferenceKeepsTheSerialPath() async throws {
        let fixture = try SnapshotReferenceTestFixture()
        defer { fixture.remove() }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let png = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 3000), format: format)
            .pngData { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 3000, height: 3000))
            }
        let reference = fixture.directory.appendingPathComponent("oversized.png")
        try png.write(to: reference)
        let result = await prepareSnapshotReference(
            capturedPNG: png,
            referenceURL: reference,
            diagnostics: true,
        )
        guard case .serial = result.outcome else {
            Issue
                .record("A matching image above eight million pixels must retain serial comparison")
            return
        }
    }

    @Test func preparedComparisonCannotApproveChangedBytes() async throws {
        let fixture = try SnapshotReferenceTestFixture()
        defer { fixture.remove() }
        let reference = fixture.directory.appendingPathComponent("reference.png")
        let original = try #require(fixture.image(.red).pngData())
        let changed = try #require(fixture.image(.blue).pngData())
        try original.write(to: reference)
        let prepared = await prepareSnapshotReference(
            capturedPNG: original,
            referenceURL: reference,
            diagnostics: true,
        )
        guard case let .matched(match) = prepared.outcome else {
            Issue.record("Identical images should prepare a reusable match")
            return
        }
        #expect(match.diagnostic == .identicalBytes)
        let strategy = SnapshotImageReference.strategy(panelFailure: nil, prepared: match)
        #expect(strategy.diffing.diffV2(original, original) == nil)
        #expect(strategy.diffing.diffV2(changed, original) != nil)
        #expect(strategy.diffing.diffV2(original, changed) != nil)
        #expect(strategy.diffing.diffV2(Data([1]), original) != nil)
    }

    @Test func preparationKeepsMissingCorruptAndDifferentReferencesOnSerialPath() async throws {
        let fixture = try SnapshotReferenceTestFixture()
        defer { fixture.remove() }
        let reference = fixture.directory.appendingPathComponent("reference.png")
        let capture = try #require(fixture.image(.red).pngData())
        let different = try #require(fixture.image(.blue).pngData())
        for data in [nil, Data([1]), different] {
            if let data { try data.write(to: reference) }
            let result = await prepareSnapshotReference(
                capturedPNG: capture,
                referenceURL: reference,
                diagnostics: true,
            )
            guard case .serial = result.outcome else {
                Issue
                    .record(
                        "Missing, corrupt, and mismatched images require authoritative serial comparison",
                    )
                continue
            }
        }
    }

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
        let bare = try #require(reference.image.pngData())
        #expect(SnapshotImageReference.comparePanels(referencePNG: bare, panels: sheet)?.message
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
        let capture = try await SnapshotImageGrid.capture(panels: sheet, named: "Invalid")
        let image = capture.image
        let layout = try #require(capture.layout)
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
            let data = try SnapshotImageReference(image: image, layout: layout).pngData()
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

/// Prepared success must not bypass the library's authoritative recording policy.
@MainActor
struct SnapshotPreparedRecordingTests {
    @Test(arguments: ["all", "failed", "missing", "never"])
    func recordingModesPreserveFilesAndIssues(mode: String) async throws {
        let fixture = try SnapshotReferenceTestFixture()
        defer { fixture.remove() }
        let captured = try #require(fixture.image(.red).pngData())
        let nearMatch = try #require(fixture.image(UIColor(
            red: 1,
            green: 1.0 / 255,
            blue: 0,
            alpha: 1,
        )).pngData())
        let different = try #require(fixture.image(.blue).pngData())
        #expect(nearMatch != captured)
        #expect(SnapshotImageReference.strategy(panelFailure: nil).diffing
            .diffV2(nearMatch, captured) == nil)
        for previous in [nil, captured, nearMatch, different] {
            let reference = fixture.directory.appendingPathComponent("policy.image.png")
            if let previous { try previous.write(to: reference) }
            let preparation = await prepareSnapshotReference(
                capturedPNG: captured,
                referenceURL: reference,
                diagnostics: true,
            )
            let match: SnapshotPreparedMatch? = if case let .matched(value) = preparation
                .outcome { value } else { nil }
            let record = try #require(SnapshotTestingConfiguration.Record(rawValue: mode))
            let shouldWrite = record == .all
                || (previous == nil && record != .never)
                || (record == .failed && previous == different)
            let shouldFail = record == .all || previous == nil || previous == different
            let failure = withSnapshotTesting(record: record) {
                verifySnapshot(
                    of: captured,
                    as: SnapshotImageReference.strategy(panelFailure: nil, prepared: match),
                    named: "image",
                    snapshotDirectory: fixture.directory.path,
                    testName: "policy",
                )
            }
            #expect((failure != nil) == shouldFail)
            let stored = try? Data(contentsOf: reference)
            #expect(stored == (shouldWrite ? captured : previous))
            if FileManager.default.fileExists(atPath: reference.path) {
                try FileManager.default.removeItem(at: reference)
            }
        }
    }
}
