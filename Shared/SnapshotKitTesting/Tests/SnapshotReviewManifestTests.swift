import Foundation
import SnapshotKit
@testable import SnapshotKitTesting
import SnapshotReviewCore
import SwiftUI
import Testing

struct SnapshotReviewManifestTests {
    @Test func suiteNamedOtherKeepsItsRootRelativePath() throws {
        let entry = try SnapshotReviewManifest.entry(
            reference: URL(fileURLWithPath: "/tmp/__Snapshots__/other/test.Loaded_iPad.png"),
            testName: "test",
            caseName: "Loaded",
            configuration: SnapshotConfiguration(layoutTraits: .tabletPortrait, device: .iPad),
        )
        #expect(entry.path.value == "test.Loaded_iPad.png")
        #expect(entry.layoutTraits == "tablet-regular-regular")
    }

    @Test func preservesExactCaseAndCombinedAxes() throws {
        let entry = try SnapshotReviewManifest.entry(
            reference: URL(
                fileURLWithPath: "/tmp/__Snapshots__/Example/other/test.Case_with_underscores_iPad_dark_bold.png",
            ),
            testName: "test()",
            caseName: "Case_with_underscores",
            configuration: SnapshotConfiguration(
                colorScheme: .dark,
                dynamicType: .accessibility3,
                legibilityWeight: .bold,
                device: .iPad,
            ),
        )
        #expect(entry.caseName == "Case_with_underscores")
        #expect(entry.path.value.hasPrefix("other/"))
        #expect(entry.variant.appearance == .other)
        #expect(entry.variant.dynamicType == "accessibility3")
        #expect(entry.frame == "iPad")
    }
}
