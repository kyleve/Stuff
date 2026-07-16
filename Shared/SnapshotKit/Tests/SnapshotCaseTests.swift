@testable import SnapshotKit
import SwiftUI
import Testing

@MainActor
struct SnapshotCaseTests {
    @Test func idIsTheName() {
        let snapshotCase = SnapshotCase(name: "States", configurations: []) { Color.red }
        #expect(snapshotCase.id == "States")
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
