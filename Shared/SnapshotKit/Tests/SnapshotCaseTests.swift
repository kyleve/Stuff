@testable import SnapshotKit
import SwiftUI
import Testing

@MainActor
struct SnapshotCaseTests {
    @Test func idIsTheName() {
        let snapshotCase = SnapshotCase(name: "States", configurations: []) { Color.red }
        #expect(snapshotCase.id == "States")
    }

    @Test func settleDefaultsToSettled() {
        let snapshotCase = SnapshotCase(name: "States", configurations: []) { Color.red }
        #expect(snapshotCase.settle == .settled)
    }

    @Test func measurementReadinessDefaultsToCaptureSettle() {
        let snapshotCase = SnapshotCase(name: "States", configurations: []) { Color.red }
        #expect(snapshotCase.measurementReadiness == .sameAsCapture)
    }

    @Test func measurementReadinessStoresTheDeclaredPolicy() {
        let snapshotCase = SnapshotCase(
            name: "States",
            configurations: [],
            measurementReadiness: .immediate,
        ) { Color.red }
        #expect(snapshotCase.measurementReadiness == .immediate)
    }

    @Test func onReadyToMeasureDefaultsToNil() {
        let snapshotCase = SnapshotCase(name: "States", configurations: []) { Color.red }
        #expect(snapshotCase.onReadyToMeasure == nil)
    }

    @Test func onReadyToMeasureStoresTheDeclaredHook() async {
        var hookRan = false
        let snapshotCase = SnapshotCase(
            name: "States",
            configurations: [],
            onReadyToMeasure: { hookRan = true },
        ) { Color.red }
        await snapshotCase.onReadyToMeasure?()
        #expect(hookRan)
    }

    @Test func settleStoresTheDeclaredMode() {
        let snapshotCase = SnapshotCase(name: "States", configurations: [], settle: .immediate) {
            Color.red
        }
        #expect(snapshotCase.settle == .immediate)
    }

    @Test func settleStoresARaisedMinimumWindow() {
        let snapshotCase = SnapshotCase(
            name: "States",
            configurations: [],
            settle: .settledAtLeast(minDuration: 1.0),
        ) {
            Color.red
        }
        #expect(snapshotCase.settle == .settledAtLeast(minDuration: 1.0))
    }

    @Test func onReadyToSnapshotDefaultsToNil() {
        let snapshotCase = SnapshotCase(name: "States", configurations: []) { Color.red }
        #expect(snapshotCase.onReadyToSnapshot == nil)
    }

    @Test func onReadyToSnapshotStoresTheDeclaredHook() async {
        var hookRan = false
        let snapshotCase = SnapshotCase(
            name: "States",
            configurations: [],
            onReadyToSnapshot: { hookRan = true },
        ) { Color.red }
        await snapshotCase.onReadyToSnapshot?()
        #expect(hookRan)
    }

    @Test func contentBuilderRunsOnlyWhenContentIsRequested() {
        var buildCount = 0
        let content: @MainActor () -> Color = {
            buildCount += 1
            return .red
        }
        let snapshotCase = SnapshotCase(name: "States", configurations: []) {
            content()
        }

        #expect(buildCount == 0)
        _ = snapshotCase.content
        #expect(buildCount == 1)
        _ = snapshotCase.content
        #expect(buildCount == 2)
    }

    @Test func previewConfigurationsExcludeAccessibilityCaptures() {
        let snapshotCase = SnapshotCase(
            name: "States",
            configurations: [
                SnapshotConfiguration(),
                SnapshotConfiguration(colorScheme: .dark),
                SnapshotConfiguration(snapshotType: .accessibility),
            ],
        ) { Color.red }
        #expect(snapshotCase.configurations.count == 3)
        #expect(snapshotCase.previewConfigurations.count == 2)
        #expect(snapshotCase.previewConfigurations.allSatisfy { $0.snapshotType == .standard })
    }
}
