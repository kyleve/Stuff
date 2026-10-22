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

        let variants = FlyoverVariant.snapshots(
            id: FlyoverVariantID("mixed"),
            snapshotCase: snapshotCase,
        )

        #expect(variants.allSatisfy { $0.exportPolicy == nil })
    }

    @Test func cutsheetVariantsPreserveCapturePolicyAndReadiness() async throws {
        var measurements = 0
        var captures = 0
        let snapshotCase = SnapshotCase.cutsheet(
            name: "Panels",
            configurations: [SnapshotConfiguration(device: .fullContent(
                name: "scroll",
                width: 100,
            ))],
            measurementReadiness: .immediate,
            onReadyToMeasure: { measurements += 1 },
            settle: .immediate,
            onReadyToSnapshot: { captures += 1 },
        ) {
            SnapshotPanel(id: .init(rawValue: "first"), label: "First") { Color.red }
            SnapshotPanel(id: .init(rawValue: "second"), label: "Second") { Color.blue }
        }
        let variants = FlyoverVariant.snapshots(
            id: FlyoverVariantID("panels"),
            snapshotCase: snapshotCase,
        )
        #expect(variants.count == 2)
        for variant in variants {
            let policy = try #require(variant.exportPolicy)
            #expect(policy.captureExtent == .fullContent)
            #expect(policy.measurementReadiness == .immediate)
            #expect(policy.settle == .immediate)
            await policy.onReadyToMeasure?()
            await policy.onReadyToSnapshot?()
        }
        #expect(measurements == 2)
        #expect(captures == 2)

        let overridden = FlyoverVariant.snapshots(
            id: FlyoverVariantID("panels"),
            snapshotCase: snapshotCase,
            exportPolicy: .hosted,
        )
        #expect(overridden.map(\.id) == variants.map(\.id))
        #expect(overridden.allSatisfy { $0.exportPolicy?.captureExtent == .viewport })
    }
}
