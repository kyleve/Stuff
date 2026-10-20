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

    @Test func snapshotContentRemainsLazy() throws {
        var buildCount = 0
        let content: @MainActor () -> Color = {
            buildCount += 1
            return .red
        }
        let snapshotCase = SnapshotCase(name: "Snapshot", configurations: []) {
            content()
        }
        let variants = FlyoverVariant.snapshots(
            id: FlyoverVariantID("snapshot"),
            snapshotCase: snapshotCase,
        )
        #expect(variants.count == 1)
        let variant = try #require(variants.first)
        #expect(variant.id == FlyoverVariantID("snapshot"))
        #expect(variant.title == "Snapshot")

        #expect(buildCount == 0)
        _ = variant.overviewContent()
        #expect(buildCount == 1)
    }

    @Test func cutsheetsBecomeSeparateLazyVariantsWithStablePanelIDs() {
        var builds = 0
        func makeCase(reversed: Bool) -> SnapshotCase {
            SnapshotCase.cutsheet(name: "Card", configurations: .componentDefaults) {
                for identity in reversed ? ["flat", "standard"] : ["standard", "flat"] {
                    SnapshotPanel(id: .init(rawValue: identity), label: identity) {
                        builds += 1
                        return Color.red
                    }
                }
            }
        }
        let variants = FlyoverVariant.snapshots(
            id: FlyoverVariantID("card"),
            snapshotCase: makeCase(reversed: false),
        )
        let reordered = FlyoverVariant.snapshots(
            id: FlyoverVariantID("card"),
            snapshotCase: makeCase(reversed: true),
        )
        #expect(builds == 0)
        #expect(variants.map(\.id.rawValue) == ["card/standard", "card/flat"])
        #expect(variants.map(\.title) == ["Card — standard", "Card — flat"])
        #expect(reordered.map(\.id) == variants.reversed().map(\.id))
        _ = variants[0].overviewContent()
        _ = variants[0].focusedContent()
        _ = variants[1].focusedContent()
        #expect(builds == 3)
    }
}
