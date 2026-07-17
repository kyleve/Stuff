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

    @Test func settleStoresTheDeclaredMode() {
        let snapshotCase = SnapshotCase(name: "States", configurations: [], settle: .immediate) {
            Color.red
        }
        #expect(snapshotCase.settle == .immediate)
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
