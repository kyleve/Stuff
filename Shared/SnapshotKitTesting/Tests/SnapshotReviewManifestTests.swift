import Foundation
import SnapshotKit
@testable import SnapshotKitTesting
import SnapshotReviewCore
import SwiftUI
import Testing

struct SnapshotReviewManifestTests {
    @Test func groupedReferencesWriteOneManifestAtTheSuiteRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = root.appendingPathComponent("__Snapshots__/Example")
        try FileManager.default.createDirectory(at: suite, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
        }
        try SnapshotReviewManifest.write(
            reference: suite.appendingPathComponent("themes/other/test.Loaded_ax3.png"),
            testName: "test",
            caseName: "Loaded",
            referenceGroup: .themes,
            configuration: SnapshotConfiguration(dynamicType: .accessibility3),
        )
        let bytes = try Data(contentsOf: suite.appendingPathComponent(SnapshotManifest.filename))
        let manifest = try ReviewJSON.decode(SnapshotManifest.self, from: bytes)
        #expect(manifest.entries.first?.path.value == "themes/other/test.Loaded_ax3.png")
        #expect(manifest.entries.first?.referenceGroup == "themes")
    }

    @Test func suiteNamedOtherKeepsItsRootRelativePath() throws {
        let entry = try SnapshotReviewManifest.entry(
            reference: URL(fileURLWithPath: "/tmp/__Snapshots__/other/test.Loaded_iPad.png"),
            testName: "test",
            caseName: "Loaded",
            referenceGroup: nil,
            configuration: SnapshotConfiguration(layoutTraits: .tabletPortrait, device: .iPad),
        )
        #expect(entry.path.value == "test.Loaded_iPad.png")
        #expect(entry.layoutTraits == "tablet-regular-regular")
    }

    @Test func preservesExactCaseAndCombinedAxes() throws {
        let entry = try SnapshotReviewManifest.entry(
            reference: URL(
                fileURLWithPath: "/tmp/__Snapshots__/Example/themes/other/test.Case_with_underscores_iPad_dark_bold.png",
            ),
            testName: "test()",
            caseName: "Case_with_underscores",
            referenceGroup: .themes,
            configuration: SnapshotConfiguration(
                colorScheme: .dark,
                dynamicType: .accessibility3,
                legibilityWeight: .bold,
                device: .iPad,
            ),
        )
        #expect(entry.caseName == "Case_with_underscores")
        #expect(entry.path.value.hasPrefix("themes/other/"))
        #expect(entry.referenceGroup == "themes")
        #expect(entry.variant.appearance == .other)
        #expect(entry.variant.dynamicType == "accessibility3")
        #expect(entry.frame == "iPad")
    }
}
