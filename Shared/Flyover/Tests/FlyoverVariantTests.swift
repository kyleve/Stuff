@testable import Flyover
import SnapshotKit
import SwiftUI
import Testing

@MainActor
struct FlyoverVariantTests {
    @Test func contentBuildersRunOnlyForTheRequestedPresentation() {
        var overviewBuildCount = 0
        var focusedBuildCount = 0
        let overview: @MainActor () -> Color = {
            overviewBuildCount += 1
            return .red
        }
        let focused: @MainActor () -> Color = {
            focusedBuildCount += 1
            return .blue
        }
        let variant = FlyoverVariant(
            id: FlyoverVariantID("lazy"),
            title: "Lazy",
        ) {
            overview()
        } focused: {
            focused()
        }

        #expect(overviewBuildCount == 0)
        #expect(focusedBuildCount == 0)

        _ = variant.overviewContent()
        #expect(overviewBuildCount == 1)
        #expect(focusedBuildCount == 0)

        _ = variant.focusedContent()
        #expect(overviewBuildCount == 1)
        #expect(focusedBuildCount == 1)
    }

    @Test func snapshotContentRemainsLazy() {
        var buildCount = 0
        let content: @MainActor () -> Color = {
            buildCount += 1
            return .red
        }
        let snapshotCase = SnapshotCase(name: "Snapshot", configurations: []) {
            content()
        }
        let variant = FlyoverVariant(
            id: FlyoverVariantID("snapshot"),
            snapshotCase: snapshotCase,
        )

        #expect(buildCount == 0)
        _ = variant.overviewContent()
        #expect(buildCount == 1)
    }

    @Test func mixedSnapshotSizingDoesNotExposeAFallbackPolicy() {
        let snapshotCase = SnapshotCase(
            name: "Mixed",
            configurations: [
                SnapshotConfiguration(
                    device: SnapshotConfiguration.Frame(
                        name: "viewport",
                        size: .fixed(CGSize(width: 100, height: 100)),
                    ),
                ),
                SnapshotConfiguration(
                    device: .fullContent(name: "full-content", width: 100),
                ),
            ],
        ) {
            Color.red
        }

        let variant = FlyoverVariant(
            id: FlyoverVariantID("mixed"),
            snapshotCase: snapshotCase,
        )

        #expect(variant.exportPolicy == nil)
    }
}
